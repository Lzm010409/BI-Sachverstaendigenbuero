/**
 * fetch-pdf.ts — lädt das Gutachten-PDF eines autoiXpert-Reports über die externalApi.
 *
 * Endpunkte (gegen die offizielle autoiXpert-Doku „Gutachten-Dokumente / API" geprüft):
 *   GET /reports/{id}/documents/report/download?format=pdf   -> Gutachten-PDF (Binary)
 *   GET /reports/{id}                                          -> Report inkl. documents[]
 *   Auth: Authorization: Bearer <AUTOIXPERT_API_TOKEN>
 *
 * Dokumenttyp: die Doku listet den HAUPT-Gutachten-Typ eindeutig als `report` (gilt für
 * Haftpflicht UND Bewertung — das Dokument heißt immer `report`; report.type unterscheidet
 * liability/valuation, nicht der Dokumenttyp). Die Fachwerte-„Zusammenfassung" steht in
 * diesem `report`-PDF. Wir laden es direkt per Typ-Shortcut; nur wenn keins existiert,
 * holen wir das Report-Objekt, um die verfügbaren Typen fürs Log zu protokollieren.
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

/** Report → Gutachten-PDF (Typ `report`). Self-diagnosing bei Fehlschlag. */
export async function fetchGutachtenPdf(reportId: string): Promise<FetchResult> {
  const { base } = conf();
  const id = encodeURIComponent(reportId);

  // Primär: Haupt-Gutachten direkt über den dokumentierten Typ-Shortcut `report`.
  const dl = await getWithBackoff(`${base}/reports/${id}/documents/report/download?format=pdf`, "application/pdf");
  if (dl) {
    const pdf = Buffer.from(await dl.arrayBuffer());
    return { status: "ok", pdf, docType: "report" };
  }

  // Kein `report`-Dokument (404). Report laden und verfügbare Typen fürs Log sammeln.
  const rep = await getWithBackoff(`${base}/reports/${id}`, "application/json");
  if (!rep) return { status: "kein_report", note: "Report-ID 404" };
  const body = (await rep.json()) as Json;
  const report = (body.report ?? body) as Json;
  const docs = Array.isArray(report.documents) ? (report.documents as Json[]) : [];
  const typen = docs.map((d) => String(d?.type ?? "")).filter(Boolean);
  return { status: "kein_dokument", note: `kein 'report'-Dokument; verfügbar: ${typen.join(", ") || "—"}` };
}
