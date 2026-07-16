import { workflow, node, trigger, splitInBatches, nextBatch, newCredential, expr } from '@n8n/workflow-sdk';

// OneDrive-Zugriff über den nativen Microsoft-OneDrive-Node (Credential
// „Microsoft Drive account", Typ microsoftOneDriveOAuth2Api) — NICHT mehr über
// generische Graph-HTTP-Requests. Das Credential ist im n8n bereits hinterlegt.

// Ingest-Basis-URL (Coolify-Domain des ingest-Dienstes). Ggf. anpassen.
const INGEST = 'https://ingest.gollenstede.app';

const scheduleTrigger = trigger({
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.3,
  config: { name: 'Täglich 03:00', parameters: { rule: { interval: [{ field: 'days', daysInterval: 1, triggerAtHour: 3 }] } } }
});

const getPending = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'Offene Aktenzeichen (HTTP)',
    parameters: { method: 'GET', url: INGEST + '/pending/gutachten', authentication: 'genericCredentialType', genericAuthType: 'httpBearerAuth' },
    credentials: { httpBearerAuth: newCredential('Warehouse Ingest') }
  }
});

const loop = splitInBatches({ version: 3, config: { name: 'Loop Over Cases', parameters: { batchSize: 1 } } });

const searchFile = node({
  type: 'n8n-nodes-base.microsoftOneDrive', version: 1.1,
  config: {
    name: 'OneDrive: Suche',
    parameters: { resource: 'file', operation: 'search', query: expr('{{ $json.ordner }}') },
    credentials: { microsoftOneDriveOAuth2Api: newCredential('Microsoft Drive account') }
  }
});

const pickFile = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Gutachten-PDF wählen', parameters: { mode: 'runOnceForAllItems', language: 'javaScript',
      jsCode: `const az = $('Loop Over Cases').first().json.aktenzeichen;
const files = $input.all().map(i => i.json).filter(x => /\\.pdf$/i.test(x.name || ''));
const pref = files.filter(x => /utachten/i.test(x.name) && !/(archiv|kopie|aufnahme|rechnung)/i.test(x.name));
const chosen = pref[0] || files.filter(x => /utachten/i.test(x.name))[0] || files[0] || null;
if (!chosen) return [{ json: { skip: true, aktenzeichen: az } }];
return [{ json: { fileId: chosen.id, name: chosen.name, aktenzeichen: az } }];`
    }
  }
});

const downloadPdf = node({
  type: 'n8n-nodes-base.microsoftOneDrive', version: 1.1,
  config: {
    name: 'OneDrive: Download',
    parameters: { resource: 'file', operation: 'download', fileId: expr('{{ $json.fileId }}'), binaryPropertyName: 'data' },
    credentials: { microsoftOneDriveOAuth2Api: newCredential('Microsoft Drive account') }
  }
});

const extractPdf = node({
  type: 'n8n-nodes-base.extractFromFile', version: 1.1,
  config: { name: 'PDF-Text extrahieren', parameters: { operation: 'pdf', binaryPropertyName: 'data', options: { joinPages: true } } }
});

const parseFachwerte = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Fachwerte parsen', parameters: { mode: 'runOnceForEachItem', language: 'javaScript',
      jsCode: `const t = String($json.text || '').replace(/\\s+/g, ' ');
const deNum = s => { if (!s) return null; const n = Number(String(s).replace(/\\./g, '').replace(',', '.')); return Number.isFinite(n) ? n : null; };
const f = re => { const m = t.match(re); return m ? deNum(m[1]) : null; };
const az = $('Gutachten-PDF wählen').item.json.aktenzeichen || (t.toUpperCase().match(/\\b(\\d{4}\\/\\d+TG)\\b/) || [])[1] || null;
const restwert = /Restwert\\s+wurde\\s+nicht\\s+ermittelt/i.test(t) ? null : f(/Restwert(?:\\s*\\(brutto\\))?\\s+EUR\\s+([\\d.,]+)/i);
const rd = t.match(/Reparaturdauer\\s+in\\s+Arbeitstagen\\s+(\\d+)/i);
const bm = t.match(/Beurteilung\\s+([A-Za-zÄÖÜäöü0-9%\\-\\s]{3,40}?)\\s+(?:Wiederbeschaffungswert|Reparaturdauer|Schadenh|EUR)/i);
const payload = {
  wiederbeschaffungswert: f(/Wiederbeschaffungswert[\\s\\S]{0,80}?EUR\\s+([\\d.,]+)/i),
  restwert,
  wertminderung: f(/Wertminderung\\s+(?:\\(netto\\)\\s+)?EUR\\s+([\\d.,]+)/i),
  reparaturkosten_netto: f(/Reparaturkosten\\s+ohne\\s+MwSt\\.?\\s+EUR\\s+([\\d.,]+)/i),
  reparaturkosten_brutto: f(/Reparaturkosten\\s+mit\\s+[\\d.,]+\\s*%\\s*MwSt\\.?\\s+EUR\\s+([\\d.,]+)/i),
  schadenhoehe_brutto: f(/Schadenh[öo]he\\s+mit\\s+[\\d.,]+\\s*%\\s*MwSt\\.?\\s+EUR\\s+([\\d.,]+)/i),
  nutzungsausfall_tagessatz: f(/Nutzungsausfall\\s+pro\\s+Tag\\s+EUR\\s+([\\d.,]+)/i),
  reparaturdauer_tage: rd ? Number(rd[1]) : null,
  beurteilung: bm ? bm[1].trim() : null
};
return { json: { aktenzeichen: az, payload, quelle_datei: $('Gutachten-PDF wählen').item.json.name || null } };`
    }
  }
});

const ingestPost = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'An Warehouse (HTTP)',
    parameters: {
      method: 'POST', url: INGEST + '/ingest/gutachten',
      authentication: 'genericCredentialType', genericAuthType: 'httpBearerAuth',
      sendBody: true, contentType: 'json', specifyBody: 'json',
      jsonBody: expr('{{ { aktenzeichen: $json.aktenzeichen, payload: $json.payload, quelle_datei: $json.quelle_datei } }}')
    },
    credentials: { httpBearerAuth: newCredential('Warehouse Ingest') }
  }
});

export default workflow('phase4-gutachten-fachwerte', 'Phase 4 — Gutachten-Fachwerte aus OneDrive')
  .add(scheduleTrigger)
  .to(getPending)
  .to(loop.onEachBatch(
    searchFile.to(pickFile).to(downloadPdf).to(extractPdf).to(parseFachwerte).to(ingestPost).to(nextBatch(loop))
  ));
