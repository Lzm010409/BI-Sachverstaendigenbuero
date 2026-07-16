import { workflow, node, trigger, languageModel, outputParser, newCredential, expr } from '@n8n/workflow-sdk';

const outlookTrigger = trigger({
  type: 'n8n-nodes-base.microsoftOutlookTrigger', version: 1,
  config: {
    name: 'Neue Mail mit Anhang',
    parameters: {
      event: 'messageReceived', output: 'simple',
      pollTimes: { item: [{ mode: 'everyHour' }] },
      filters: { hasAttachments: true, readStatus: 'unread' },
      options: { downloadAttachments: true, attachmentsPrefix: 'attachment_' }
    },
    credentials: { microsoftOutlookOAuth2Api: newCredential('Microsoft Outlook') }
  }
});

const normAttach = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Anhang → data', parameters: { mode: 'runOnceForEachItem', language: 'javaScript',
      jsCode: `const bin = $input.item.binary || {};
const first = bin.attachment_0 || bin.data || Object.values(bin)[0];
if (!first) return { json: { _skip: true } };
return { json: { _subject: $json.subject || '', _from: ($json.from && $json.from.emailAddress && $json.from.emailAddress.address) || '' }, binary: { data: first } };`
    }
  }
});

const ocr = node({
  type: 'n8n-nodes-base.mistralAi', version: 1,
  config: {
    name: 'Mistral OCR',
    parameters: { resource: 'document', operation: 'extractText', model: 'mistral-ocr-latest', documentType: 'document_url', inputType: 'binary', binaryProperty: 'data' },
    credentials: { mistralCloudApi: newCredential('Mistral Cloud') }
  }
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
    parameters: {
      promptType: 'define', hasOutputParser: true,
      text: expr("Du extrahierst Fakten aus einem Versicherer-Schreiben (OCR-Text unten). Ist es ein Kürzungs-/Regulierungsschreiben, das Sachverständigenkosten kürzt, setze ist_kuerzungsschreiben=true und extrahiere: aktenzeichen (Format MMJJ/NummerTG, aus der Rechnungsnummer; Leerzeichen entfernen), kuerzungsbetrag (EUR, der als 'Kürzungsbetrag' genannte Betrag), versicherer, schadennummer, datum (YYYY-MM-DD), sachverstaendigenkosten (gezahlt), zahlungsbetrag. Unbekanntes = null. Nur JSON.\\n\\nOCR-TEXT:\\n{{ JSON.stringify($json) }}")
    },
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
  config: {
    name: 'Deal suchen', parameters: { resource: 'deal', operation: 'search', term: expr('{{ $json.output.aktenzeichen }}'), exactMatch: true, returnAll: false, limit: 1 },
    credentials: { pipedriveApi: newCredential('Pipedrive') }
  }
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
const content = 'Kürzungsschreiben ' + (o.versicherer || '') + ': Kürzungsbetrag ' + betrag + ' EUR' + (o.datum ? ' (' + o.datum + ')' : '') + (o.schadennummer ? ', Schaden-Nr. ' + o.schadennummer : '') + '. Gezahlte SV-Kosten: ' + (o.sachverstaendigenkosten ?? '?') + ' EUR.';
return { json: { deal_id: dealId, content, letter_key, aktenzeichen: az || null, quelle: 'outlook', payload: o } };`
    }
  }
});

const noteCreate = node({
  type: 'n8n-nodes-base.pipedrive', version: 2,
  config: {
    name: 'Pipedrive-Notiz', parameters: { resource: 'note', operation: 'create', content: expr('{{ $json.content }}'), additionalFields: { deal_id: expr('{{ $json.deal_id }}'), pinned_to_deal_flag: true } },
    credentials: { pipedriveApi: newCredential('Pipedrive') }
  }
});

const upsert = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: {
    name: 'Upsert Warehouse',
    parameters: { operation: 'upsert', schema: { __rl: true, mode: 'name', value: 'raw' }, table: { __rl: true, mode: 'name', value: 'kuerzungsschreiben' }, columns: { mappingMode: 'autoMapInputData', value: null, matchingColumns: ['letter_key'] } },
    credentials: { postgres: newCredential('Warehouse Postgres') }
  }
});

export default workflow('phase5-kuerzungsschreiben', 'Phase 5 — Kürzungsschreiben → Pipedrive + Warehouse')
  .add(outlookTrigger).to(normAttach).to(ocr).to(llm).to(isKuerzung.onTrue(dealSearch.to(buildNote).to(noteCreate)))
  .add(buildNote).to(upsert);
