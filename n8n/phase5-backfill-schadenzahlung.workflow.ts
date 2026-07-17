import { workflow, node, trigger, splitInBatches, nextBatch, languageModel, newCredential, expr } from '@n8n/workflow-sdk';

// Reader-Workflow für den historischen Kürzungs-Backfill (n8n-ID qU8wCN2uqlgaz9rs).
// Zweck: n8n hat den funktionierenden OneDrive-Zugang ("Microsoft Drive account");
// die Session nicht. Dieser Workflow LIEST OneDrive → Mistral-OCR → Mistral-LLM
// und gibt kompakte Datensätze aus. Ausgelesen wird über die Execution-Daten
// (Knoten "Sammeln"); geschrieben wird NICHT von hier, sondern via sql/019
// (Deploy-Kette), damit die echte Kürzung = fakturiert − gezahlt (sevDesk) rechnet.
//
// Recall statt Dateiname-Raten: es wird über MEHRERE Suchbegriffe gefahren
// (Kürzungsschreiben heißen uneinheitlich — "Schadenzahlung", "Vers ABRECHNUNG",
// "… Kürzung SV Kosten", "Regulierungsschreiben", "Vers Ablehnung SVK"). Ein
// "Suchbegriffe"-Node fächert die Terme auf, der Suche-Node läuft je Term einmal
// (Union), "Kandidaten" dedupliziert über fileId. Das Aktenzeichen kommt aus dem
// Ordnerpfad .../Gutachten/JJJJ/MM/<az>/, nicht aus der LLM-Ausgabe; nur PDFs in
// einem Fallordner werden per OCR gelesen (Kostenbremse).
// Download gedrosselt über SplitInBatches (batchSize 3), sonst überlastet der
// Parallel-Download OneDrive. Kein strenger Output-Parser (bricht bei Abweichung);
// stattdessen tolerantes JSON.parse in "Sammeln".
//
// Hinweis: Manuelle Executions werden bei inaktiven Workflows nicht gespeichert;
// daher Zeitplan-Trigger + Publish, und Ausführung im Production-Mode, damit die
// Execution abfragbar bleibt. Nach dem Backfill wieder unpublishen.

const start = trigger({ type: 'n8n-nodes-base.manualTrigger', version: 1, config: { name: 'Start', position: [0, 300] } });
const zeitplan = trigger({ type: 'n8n-nodes-base.scheduleTrigger', version: 1.3, config: { name: 'Zeitplan', position: [0, 120], parameters: { rule: { interval: [{ field: 'days', daysInterval: 1, triggerAtHour: 4 }] } } } });

// Editierbare Suchbegriffe. OneDrive-Suche matcht Datei-Name UND -Inhalt.
const terms = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Suchbegriffe', position: [110, 300],
    parameters: { language: 'javaScript', jsCode: `const terme = ['Schadenzahlung','Kürzung','Regulierung','Ablehnung','Abrechnung','SVK'];
return terme.map(t => ({ json: { term: t } }));` }
  }
});

const search = node({
  type: 'n8n-nodes-base.microsoftOneDrive', version: 1.1,
  config: {
    name: 'Suche', position: [220, 300],
    parameters: { resource: 'file', operation: 'search', query: expr('{{ $json.term }}') },
    credentials: { microsoftOneDriveOAuth2Api: newCredential('Microsoft Drive account') }
  }
});

const candidates = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Kandidaten', position: [440, 300],
    parameters: { language: 'javaScript', jsCode: `// Union aller Term-Treffer -> dedupe (fileId) -> nur PDFs in einem Fallordner,
// deren DATEINAME auf ein Versicherer-Abrechnungs-/Regulierungs-/Ablehnungsschreiben
// deutet. Namensfilter = Kostenbremse: die OneDrive-Suche matcht auch Datei-INHALT,
// wodurch generische Terme (Abrechnung/Regulierung) hunderte Abtretungs-/Widerruf-
// Formulare treffen (1528 Roh-Treffer -> 121 echte Schreiben). Stellungnahme = unsere
// Erwiderung ohne Zahlbetrag -> separate LF3-Quelle, hier ausgeschlossen.
const KEEP = /(regulier|k[uü]rzung|abrechnung|schadenzahlung|ablehnung|\\bsvk\\b|sv[ _-]?kosten|pr[uü]fbericht|vers[ _])/i;
const DROP = /(stellungnahme|abtret|abtritt|widerruf|blanko|vollmacht)/i;
const out = [];
const seen = new Set();
for (const it of $input.all()) {
  const x = it.json;
  const name = x.name || '';
  if (!/\\.pdf$/i.test(name)) continue;
  if (!KEEP.test(name) || DROP.test(name)) continue;
  if (!x.id || seen.has(x.id)) continue;
  seen.add(x.id);
  const url = decodeURIComponent(x.webUrl || '');
  const m = url.match(/\\/(\\d{4})_(\\d+)TG\\//);
  const folderAz = m ? (m[1] + '/' + m[2] + 'TG') : null;
  if (!folderAz) continue;
  out.push({ json: { fileId: x.id, name, webUrl: x.webUrl, folderAz } });
}
return out;` }
  }
});

const loop = splitInBatches({ version: 3, config: { name: 'Batch', position: [660, 300], parameters: { batchSize: 3 } } });

const download = node({
  type: 'n8n-nodes-base.microsoftOneDrive', version: 1.1,
  config: {
    name: 'Download', position: [880, 300], onError: 'continueRegularOutput',
    parameters: { resource: 'file', operation: 'download', fileId: expr('{{ $json.fileId }}'), binaryPropertyName: 'data' },
    credentials: { microsoftOneDriveOAuth2Api: newCredential('Microsoft Drive account') }
  }
});

const ocr = node({
  type: 'n8n-nodes-base.mistralAi', version: 1,
  config: {
    name: 'OCR', position: [1100, 300], onError: 'continueRegularOutput',
    parameters: { resource: 'document', operation: 'extractText', model: 'mistral-ocr-latest', documentType: 'document_url', inputType: 'binary', binaryProperty: 'data', options: {} },
    credentials: { mistralCloudApi: newCredential('Mistral Cloud account') }
  }
});

const model = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatMistralCloud', version: 1,
  config: { name: 'Mistral Chat', position: [1100, 520], parameters: { model: 'mistral-large-latest', options: { temperature: 0 } }, credentials: { mistralCloudApi: newCredential('Mistral Cloud account') } }
});

const extract = node({
  type: '@n8n/n8n-nodes-langchain.chainLlm', version: 1.9,
  config: {
    name: 'Extract', position: [1320, 300], onError: 'continueRegularOutput',
    parameters: { promptType: 'define', hasOutputParser: false, text: expr("Du extrahierst Fakten aus einem Versicherer-Schreiben (OCR-Text unten). Ist es ein Kuerzungs-/Regulierungsschreiben, das Sachverstaendigenkosten kuerzt, setze ist_kuerzungsschreiben=true und extrahiere: aktenzeichen (Format MMJJ/NummerTG), kuerzungsbetrag, versicherer, schadennummer, datum (YYYY-MM-DD), sachverstaendigenkosten (gezahlt), zahlungsbetrag. Unbekanntes = null. NUR ein JSON-Objekt, keine Erklaerung.\\n\\nOCR-TEXT:\\n{{ JSON.stringify($json) }}") },
    subnodes: { model: model }
  }
});

const collect = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Sammeln', position: [1540, 300],
    parameters: { mode: 'runOnceForEachItem', language: 'javaScript', jsCode: `let o = $json.output;
if (o == null || typeof o !== 'object') {
  let txt = String($json.text != null ? $json.text : (o != null ? o : '')).trim();
  txt = txt.replace(/^\`\`\`json/i, '').replace(/^\`\`\`/, '').replace(/\`\`\`$/, '').trim();
  try { o = JSON.parse(txt); } catch (e) { o = { _parseError: true, raw: txt.slice(0, 400) }; }
}
let k = {};
try { k = $('Kandidaten').item.json || {}; } catch (e) {}
return { json: { folderAz: k.folderAz || null, datei: k.name || null, webUrl: k.webUrl || null, llm: o } };` }
  }
});

export default workflow('phase5-backfill-schadenzahlung', 'Phase 5 Backfill — Schadenzahlung (Reader)')
  .add(start).to(terms)
  .add(zeitplan).to(terms)
  .add(terms).to(search)
  .add(search).to(candidates)
  .to(loop.onEachBatch(download.to(ocr).to(extract).to(collect).to(nextBatch(loop))));
