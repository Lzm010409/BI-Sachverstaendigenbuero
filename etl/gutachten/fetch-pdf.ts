/**
 * fetch-pdf.ts — lädt das Gutachten-PDF eines autoiXpert-Reports über die externalApi.
 *
 * Endpunkte (gegen den LIVE-n8n-Workflow „autoiXpert DAT-Kalkulation Download"
 * verifiziert, nicht aus dem Gedächtnis):
 *   GET /externalApi/v1/reports/{id}                       -> Report inkl. documents[]
 *   GET /externalApi/v1/reports/{id}/documents/{docId}/download  -> PDF (Binary)
 *   Auth: Bearer <AUTOIXPERT_API_TOKEN>
 *
 * Die Fachwerte (WBW/Restwert/Wertminderung/…) stehen auf der „Zusammenfassung"-Seite
 * des HAUPT-Gutachtens — NICHT in den Anhang-Dokumenten (dat_damage_calculation etc.).
 * Der richtige Dokumenttyp-Name ist API-seitig nicht 100 % dokumentiert, daher wählt
 * pickGutachtenDoc() heuristisch (Typ-Kandidaten + Titel-Match) und liefert bei
 * Misserfolg die verfügbaren Dokumente zurück — self-diagnosing wie der n8n-Workflow.
 *
 * Läuft im Coolify-etl-Container (app.autoixpert.de dort erreichbar). NUR GET.
 */
type Json = Record<string, unknown>;

function conf(): { base: string; token: string } {
  const base = process.env.AUTOIXPERT_API_BASE ?? "https://app.autoixpert.de/externalApi/v1";
  const token = process.env.AUTOIXPERT_API_TOKEN;
  if (!token) throw new Error("Fehlt: Umgebungsvariable AUTOIXPERT_API_TOKEN");
  return { base: base.replace(/\/+$/, ""), token };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const norm = (s: unknown) => String(s ?? "").toLowerCase().replace(/[^a-z]/g, "");

// Kandidaten für den Typ des Haupt-Gutachtens (das die Zusammenfassungsseite enthält).
// Anhänge wie dat_damage_calculation/custom_residual_value_bid_list bewusst NICHT.
const TYP_KANDIDATEN = [
  "expertreport", "report", "gutachten", "liabilityreport", "valuationreport",
  "appraisalreport", "damagereport", "expertise",
].map(norm);
const TITEL_MATCH = /gutachten|bewertung|haftpflicht|schadengutachten/i;

export interface DocPick {
  documentId: string | null;
  type: string | null;
  title: string | null;
  available: Array<{ type: string; title: string }>;
}

/** Wählt aus documents[] das Haupt-Gutachten (Typ-Kandidat, sonst Titel-Match). */
export function pickGutachtenDoc(report: Json): DocPick {
  const docs = Array.isArray(report.documents) ? (report.documents as Json[]) : [];
  const available = docs.map((d) => ({ type: String(d?.type ?? ""), title: String(d?.title ?? "") }));
  const id = (d: Json) => (d?.id ?? d?._id) as string | undefined;

  let hit = docs.find((d) => TYP_KANDIDATEN.includes(norm(d?.type)));
  if (!hit) hit = docs.find((d) => TITEL_MATCH.test(String(d?.title ?? "")));
  if (!hit) return { documentId: null, type: null, title: null, available };
  return { documentId: id(hit) ?? null, type: String(hit.type ?? ""), title: String(hit.title ?? ""), available };
}

async function getWithBackoff(url: string, accept: string, maxRetries = 5): Promise<Response | null> {
  const { token } = conf();
  let attempt = 0;
  for (;;) {
    const res = await fetch(url, { headers: { Accept: accept, Authorization: `Bearer ${token}` } });
    if (res.ok) return res;
    if (res.status === 404) return null;
    if ((res.status === 429 || res.status >= 500) && attempt < maxRetries) {
      const retryAfter = Number(res.headers.get("retry-after"));
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : Math.min(1000 * 2 ** attempt, 30_000));
      attempt++;
      continue;
    }
    const text = await res.text().catch(() => "");
    throw new Error(`autoiXpert ${url} -> HTTP ${res.status} ${text.slice(0, 160)}`);
  }
}

export interface FetchResult {
  status: "ok" | "kein_report" | "kein_dokument";
  pdf?: Buffer;
  docType?: string | null;
  note?: string;
}

/** Report → Gutachten-Dokument finden → PDF laden. Null-tolerant je Stufe. */
export async function fetchGutachtenPdf(reportId: string): Promise<FetchResult> {
  const { base } = conf();
  const repRes = await getWithBackoff(`${base}/reports/${encodeURIComponent(reportId)}`, "application/json");
  if (!repRes) return { status: "kein_report", note: "Report-ID 404" };
  const body = (await repRes.json()) as Json;
  const report = (body.report ?? body) as Json;

  const pick = pickGutachtenDoc(report);
  if (!pick.documentId) {
    return { status: "kein_dokument", note: `verfügbar: ${pick.available.map((a) => a.type || a.title).join(", ") || "—"}` };
  }
  const dlRes = await getWithBackoff(
    `${base}/reports/${encodeURIComponent(reportId)}/documents/${encodeURIComponent(pick.documentId)}/download`,
    "application/pdf",
  );
  if (!dlRes) return { status: "kein_dokument", note: `Download 404 (Typ ${pick.type})` };
  const pdf = Buffer.from(await dlRes.arrayBuffer());
  return { status: "ok", pdf, docType: pick.type };
}
