import { workflow, node, trigger, languageModel, outputParser, newCredential, expr } from '@n8n/workflow-sdk';

const INGEST = 'https://ingest.gollenstede.app';
const MAILBOX = 'abrechnungsschreiben@gollenstede-sachverstand.de';
const GRAPH = 'https://graph.microsoft.com/v1.0/users/' + MAILBOX;

// --- Intake: app-only Graph-Poll des GETEILTEN Postfachs abrechnungsschreiben@ ---
// Ersetzt den früheren delegierten Outlook-Trigger (microsoftOutlookTrigger), der nur
// das eigene Postfach des angemeldeten Nutzers sehen konnte und deshalb das geteilte
// Postfach nicht erreichte. Jetzt: OAuth2 *Client Credentials* (app-only). „RBAC for
// Applications" (Exchange Online) begrenzt den Zugriff auf genau dieses eine Postfach —
// Rolle „Application Mail.Read" liest, „Application Mail.ReadWrite" markiert die Mail als
// gelesen (Dedup, s. markRead). n8n-Credential: generische „OAuth2 API", Grant Type
// Client Credentials, Token-URL des Tenants, Scope https://graph.microsoft.com/.default.
const graphCred = () => newCredential('Microsoft Graph App-Only');

const schedule = trigger({
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.3,
  config: { name: 'Stündlich Abrechnungspostfach', parameters: { rule: { interval: [{ field: 'hours', hoursInterval: 1 }] } } }
});

const listMails = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'Graph: Mails auflisten',
    parameters: {
      method: 'GET', url: GRAPH + '/mailFolders/inbox/messages',
      authentication: 'genericCredentialType', genericAuthType: 'oAuth2Api',
      sendQuery: true, specifyQuery: 'keypair',
      queryParameters: { parameters: [
        { name: '$filter', value: 'isRead eq false and hasAttachments eq true' },
        { name: '$select', value: 'id,subject,from,hasAttachments,receivedDateTime' },
        { name: '$top', value: '25' }
      ] }, options: {}
    },
    credentials: { oAuth2Api: graphCred() }
  }
});

const splitMails = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Mails aufteilen', parameters: { mode: 'runOnceForAllItems', language: 'javaScript',
    jsCode: `const out = [];
for (const it of $input.all()) {
  const msgs = (it.json && it.json.value) || [];
  for (const m of msgs) out.push({ json: m });
}
return out;` } }
});

const getAttachments = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'Graph: Anhänge holen',
    parameters: { method: 'GET', url: expr('=' + GRAPH + '/messages/{{ $json.id }}/attachments'),
      authentication: 'genericCredentialType', genericAuthType: 'oAuth2Api', options: {} },
    credentials: { oAuth2Api: graphCred() }
  }
});

// Ersten PDF-Anhang aus der Graph-Antwort ziehen, base64 → binary „Files" (das Feld,
// das Mistral OCR liest). Trägt die Message-ID mit (für markRead) und die Quelle.
const decode = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Anhang → Files (Graph)', parameters: { mode: 'runOnceForEachItem', language: 'javaScript',
    jsCode: `const atts = (($json.value) || []).filter(a => String((a && a['@odata.type']) || '').toLowerCase().includes('fileattachment'));
const pdf = atts.find(a => /pdf/i.test((a && a.contentType) || '') || /\\.pdf$/i.test((a && a.name) || '')) || atts[0];
let msg = {};
try { msg = $('Mails aufteilen').item.json || {}; } catch (e) {}
if (!pdf || !pdf.contentBytes) { return { json: { _skip: true, _messageId: (msg && msg.id) || null } }; }
return { json: { _messageId: (msg && msg.id) || null, _subject: (msg && msg.subject) || '', _from: (msg && msg.from && msg.from.emailAddress && msg.from.emailAddress.address) || '', quelle: 'graph-abrechnungspostfach' }, binary: { Files: { data: pdf.contentBytes, fileName: (pdf && pdf.name) || 'anhang.pdf', mimeType: (pdf && pdf.contentType) || 'application/pdf' } } };` } }
});

// Dedup: Mail als gelesen markieren (der Poll filtert isRead eq false). Braucht die
// Application-Rolle Mail.ReadWrite; onError=continue, damit ein fehlendes ReadWrite den
// Lauf nicht bricht (dann greift ersatzweise die letter_key-Idempotenz im Ingest).
const markRead = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'Graph: Als gelesen markieren',
    parameters: { method: 'PATCH', url: expr('=' + GRAPH + '/messages/{{ $json._messageId }}'),
      authentication: 'genericCredentialType', genericAuthType: 'oAuth2Api',
      sendBody: true, contentType: 'json', specifyBody: 'json', jsonBody: expr('{{ { isRead: true } }}'), options: {} },
    credentials: { oAuth2Api: graphCred() }
  }
});

const ocr = node({
  type: 'n8n-nodes-base.mistralAi', version: 1,
  config: { name: 'Mistral OCR', parameters: { resource: 'document', operation: 'extractText', model: 'mistral-ocr-latest', documentType: 'document_url', inputType: 'binary', binaryProperty: 'Files' }, credentials: { mistralCloudApi: newCredential('Mistral Cloud') } }
});

const mistralModel = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatMistralCloud', version: 1,
  config: { name: 'Mistral Chat', parameters: { model: 'mistral-large-latest', options: { temperature: 0 } }, credentials: { mistralCloudApi: newCredential('Mistral Cloud') } }
});

const parser = outputParser({
  type: '@n8n/n8n-nodes-langchain.outputParserStructured', version: 1.3,
  config: { name: 'Schema', parameters: { schemaType: 'fromJson', jsonSchemaExample: JSON.stringify({ ist_kuerzungsschreiben: true, aktenzeichen: '0224/1101TG', kuerzungsbetrag: 831.57, versicherer: 'Allianz Versicherungs-AG', schadennummer: 'AS2024-50163649', datum: '2024-02-17', sachverstaendigenkosten: 301.55, zahlungsbetrag: 4481.73 }) } }
});

const llm = node({
  type: '@n8n/n8n-nodes-langchain.chainLlm', version: 1.9,
  config: {
    name: 'Kürzung extrahieren',
    parameters: { promptType: 'define', hasOutputParser: true, text: expr("Du extrahierst Fakten aus einem Versicherer-Schreiben (OCR-Text unten). Ist es ein Kürzungs-/Regulierungsschreiben, das Sachverständigenkosten kürzt, setze ist_kuerzungsschreiben=true und extrahiere: aktenzeichen (Format MMJJ/NummerTG, aus der Rechnungsnummer; Leerzeichen entfernen), kuerzungsbetrag (EUR, der als 'Kürzungsbetrag' genannte Betrag), versicherer, schadennummer, datum (YYYY-MM-DD), sachverstaendigenkosten (gezahlt), zahlungsbetrag. Unbekanntes = null. Nur JSON.\\n\\nOCR-TEXT:\\n{{ JSON.stringify($json) }}") },
    subnodes: { model: mistralModel, outputParser: parser }
  }
});

const isKuerzung = node({
  type: 'n8n-nodes-base.if', version: 2.2,
  config: {
    name: 'Ist Kürzungsschreiben?',
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [
        { leftValue: expr('{{ $json.output.ist_kuerzungsschreiben }}'), operator: { type: 'boolean', operation: 'true' } },
        { leftValue: expr('{{ $json.output.aktenzeichen }}'), operator: { type: 'string', operation: 'exists' } }
      ], combinator: 'and' } }
  }
});

const dealSearch = node({
  type: 'n8n-nodes-base.pipedrive', version: 2,
  config: { name: 'Deal suchen', parameters: { resource: 'deal', operation: 'search', term: expr('{{ $json.output.aktenzeichen }}'), exactMatch: true, returnAll: false, limit: 1 }, credentials: { pipedriveApi: newCredential('Pipedrive') } }
});

const buildNote = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Notiz + Datensatz bauen', parameters: { mode: 'runOnceForEachItem', language: 'javaScript',
      jsCode: `const o = $('Kürzung extrahieren').item.json.output || {};
const dealId = $json.id || null;
const az = String(o.aktenzeichen || '').toUpperCase().replace(/\\s/g, '');
const betrag = o.kuerzungsbetrag != null ? o.kuerzungsbetrag : '';
const letter_key = az + '|' + (o.schadennummer || '') + '|' + betrag;
let quelle = 'manuell';
try { const g = $('Anhang → Files (Graph)').item.json; if (g && g.quelle) quelle = g.quelle; } catch (e) {}
const content = 'Kürzungsschreiben ' + (o.versicherer || '') + ': Kürzungsbetrag ' + betrag + ' EUR' + (o.datum ? ' (' + o.datum + ')' : '') + (o.schadennummer ? ', Schaden-Nr. ' + o.schadennummer : '') + '. Gezahlte SV-Kosten: ' + (o.sachverstaendigenkosten ?? '?') + ' EUR.';
return { json: { deal_id: dealId, content, letter_key, aktenzeichen: az || null, quelle, payload: o } };`
    }
  }
});

const noteCreate = node({
  type: 'n8n-nodes-base.pipedrive', version: 2,
  config: { name: 'Pipedrive-Notiz', parameters: { resource: 'note', operation: 'create', content: expr('{{ $json.content }}'), additionalFields: { deal_id: expr('{{ $json.deal_id }}'), pinned_to_deal_flag: true } }, credentials: { pipedriveApi: newCredential('Pipedrive') } }
});

const ingestPost = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'An Warehouse (HTTP)',
    parameters: {
      method: 'POST', url: INGEST + '/ingest/kuerzung',
      authentication: 'genericCredentialType', genericAuthType: 'httpBearerAuth',
      sendBody: true, contentType: 'json', specifyBody: 'json',
      jsonBody: expr('{{ { letter_key: $json.letter_key, aktenzeichen: $json.aktenzeichen, payload: $json.payload, quelle: $json.quelle } }}')
    },
    credentials: { httpBearerAuth: newCredential('Warehouse Ingest') }
  }
});

// --- Backfill-Zweig: historische Kürzungsschreiben aus OneDrive ---------------
// Manueller Start durchsucht die OneDrive nach „Kürzung"-PDFs (nativer OneDrive-
// Node, Credential „Microsoft Drive account") und speist sie in dieselbe
// OCR→LLM→Pipedrive+Warehouse-Kette wie die laufenden Mail-Anhänge.
const backfillStart = trigger({
  type: 'n8n-nodes-base.manualTrigger', version: 1,
  config: { name: 'Backfill: Start', parameters: {} }
});

const backfillSearch = node({
  type: 'n8n-nodes-base.microsoftOneDrive', version: 1.1,
  config: {
    name: 'Backfill: OneDrive Suche',
    parameters: { resource: 'file', operation: 'search', query: 'Kürzung' },
    credentials: { microsoftOneDriveOAuth2Api: newCredential('Microsoft Drive account') }
  }
});

const backfillFilter = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Backfill: Dateien', parameters: { language: 'javaScript',
      jsCode: `const out = [];
for (const it of $input.all()) {
  const x = it.json;
  if (/\\.pdf$/i.test(x.name || '') && !/(archiv|kopie)/i.test(x.name || '')) out.push({ json: { fileId: x.id, name: x.name } });
}
return out;`
    }
  }
});

const backfillDownload = node({
  type: 'n8n-nodes-base.microsoftOneDrive', version: 1.1,
  config: {
    name: 'Backfill: OneDrive Download',
    parameters: { resource: 'file', operation: 'download', fileId: expr('{{ $json.fileId }}'), binaryPropertyName: 'Files' },
    credentials: { microsoftOneDriveOAuth2Api: newCredential('Microsoft Drive account') }
  }
});

export default workflow('phase5-kuerzungsschreiben', 'Phase 5 — Kürzungsschreiben → Pipedrive + Warehouse')
  // Laufender Intake: Graph-Poll des geteilten Postfachs → OCR → LLM → (Kürzung) Pipedrive + Warehouse.
  .add(schedule).to(listMails).to(splitMails).to(getAttachments).to(decode).to(ocr).to(llm).to(isKuerzung.onTrue(dealSearch.to(buildNote).to(noteCreate)))
  // Dedup-Seitenzweig: verarbeitete Mail als gelesen markieren.
  .add(decode).to(markRead)
  .add(buildNote).to(ingestPost)
  // Backfill historischer Schreiben aus OneDrive (manuell).
  .add(backfillStart).to(backfillSearch).to(backfillFilter).to(backfillDownload).to(ocr);
