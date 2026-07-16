import { workflow, node, trigger, splitInBatches, nextBatch, newCredential, expr } from '@n8n/workflow-sdk';

const scheduleTrigger = trigger({
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.3,
  config: { name: 'Täglich 03:00', parameters: { rule: { interval: [{ field: 'days', daysInterval: 1, triggerAtHour: 3 }] } } }
});

const getPending = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: {
    name: 'Offene Aktenzeichen',
    parameters: {
      operation: 'executeQuery',
      query: "SELECT az AS aktenzeichen, replace(az,'/','_') AS ordner, '20'||substring(az from 3 for 2) AS jahr, substring(az from 1 for 2) AS monat FROM (SELECT upper(regexp_replace(payload->>'title','\\s','','g')) AS az, payload->>'status' AS status FROM raw.pipedrive_deals) d WHERE d.status='won' AND d.az ~ '^[0-9]{4}/[0-9]+TG$' AND NOT EXISTS (SELECT 1 FROM raw.gutachten_fachwerte f WHERE f.aktenzeichen=d.az) LIMIT 25"
    },
    credentials: { postgres: newCredential('Warehouse Postgres') }
  }
});

const loop = splitInBatches({ version: 3, config: { name: 'Loop Over Cases', parameters: { batchSize: 1 } } });

const searchFile = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'Suche Gutachten (Graph)',
    parameters: {
      method: 'GET',
      url: expr("https://graph.microsoft.com/v1.0/me/drive/root/search(q='{{ $json.ordner }}')"),
      authentication: 'genericCredentialType', genericAuthType: 'oAuth2Api'
    },
    credentials: { oAuth2Api: newCredential('Microsoft Graph OAuth2') }
  }
});

const pickFile = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Gutachten-PDF wählen', parameters: { mode: 'runOnceForEachItem', language: 'javaScript',
      jsCode: `const az = $('Loop Over Cases').item.json.aktenzeichen;
const files = ($json.value || []).filter(x => /\\.pdf$/i.test(x.name || ''));
const pref = files.filter(x => /utachten/i.test(x.name) && !/(archiv|kopie|aufnahme)/i.test(x.name));
const chosen = pref[0] || files.filter(x => /utachten/i.test(x.name))[0] || null;
if (!chosen) return { json: { skip: true, aktenzeichen: az } };
return { json: { downloadUrl: chosen['@microsoft.graph.downloadUrl'], name: chosen.name, aktenzeichen: az } };`
    }
  }
});

const downloadPdf = node({
  type: 'n8n-nodes-base.httpRequest', version: 4.4,
  config: {
    name: 'PDF laden',
    parameters: {
      method: 'GET', url: expr('{{ $json.downloadUrl }}'), authentication: 'none',
      options: { response: { response: { responseFormat: 'file', outputPropertyName: 'data' } } }
    }
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

const upsert = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: {
    name: 'Upsert Fachwerte',
    parameters: {
      operation: 'upsert', schema: { __rl: true, mode: 'name', value: 'raw' },
      table: { __rl: true, mode: 'name', value: 'gutachten_fachwerte' },
      columns: { mappingMode: 'autoMapInputData', value: null, matchingColumns: ['aktenzeichen'] }
    },
    credentials: { postgres: newCredential('Warehouse Postgres') }
  }
});

export default workflow('phase4-gutachten-fachwerte', 'Phase 4 — Gutachten-Fachwerte aus OneDrive')
  .add(scheduleTrigger)
  .to(getPending)
  .to(loop.onEachBatch(
    searchFile.to(pickFile).to(downloadPdf).to(extractPdf).to(parseFachwerte).to(upsert).to(nextBatch(loop))
  ));
