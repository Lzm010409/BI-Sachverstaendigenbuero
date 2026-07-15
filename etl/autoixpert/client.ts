/**
 * client.ts — minimaler autoiXpert-externalApi-Client (read-only) für die
 * Extraktion eines einzelnen Gutachtens (Report).
 *
 * Endpunkt/Auth sind gegen die LIVE-Konfiguration des bestehenden n8n-Workflows
 * „autoiXpert DAT-Kalkulation Download" verifiziert (nicht aus dem Gedächtnis):
 *   GET https://app.autoixpert.de/externalApi/v1/reports/{id}
 *   Authorization: Bearer <AUTOIXPERT_API_TOKEN>   (httpBearerAuth)
 * Die Antwort ist das Report-Objekt, in der Praxis in `{ report: {...} }` gewrappt
 * (siehe echtes Sample) — hier wird `.report` ausgepackt, falls vorhanden.
 *
 * Läuft im Coolify-`etl`-Container (app.autoixpert.de ist von dort erreichbar; aus
 * der Web-Session ist der Egress per Netzwerk-Policy geblockt). NUR GET.
 * Exponentielles Backoff bei 429/5xx (gleiches Muster wie sevDesk/Pipedrive).
 *
 * API-Details vor Änderungen gegen die aktuelle autoiXpert-Doku prüfen.
 */

type Json = Record<string, unknown>;

function conf(): { base: string; token: string } {
  const base = process.env.AUTOIXPERT_API_BASE ?? "https://app.autoixpert.de/externalApi/v1";
  const token = process.env.AUTOIXPERT_API_TOKEN;
  if (!token) throw new Error("Fehlt: Umgebungsvariable AUTOIXPERT_API_TOKEN");
  return { base: base.replace(/\/+$/, ""), token };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Holt ein einzelnes Gutachten per Report-ID. Liefert das (ggf. aus `.report`
 * ausgepackte) Report-Objekt, oder `null` bei HTTP 404 (unbekannte/gelöschte ID) —
 * so kippt ein einzelnes fehlendes Gutachten nicht den ganzen Lauf.
 */
export async function fetchReport(id: string, maxRetries = 6): Promise<Json | null> {
  const { base, token } = conf();
  const url = `${base}/reports/${encodeURIComponent(id)}`;
  let attempt = 0;
  for (;;) {
    const res = await fetch(url, {
      headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
    });
    if (res.ok) {
      const body = (await res.json()) as Json;
      const report = (body.report ?? body) as Json;
      return report;
    }
    if (res.status === 404) return null;
    if ((res.status === 429 || res.status >= 500) && attempt < maxRetries) {
      const retryAfter = Number(res.headers.get("retry-after"));
      const wait = Number.isFinite(retryAfter) && retryAfter > 0
        ? retryAfter * 1000
        : Math.min(1000 * 2 ** attempt, 30_000);
      await sleep(wait);
      attempt++;
      continue;
    }
    const text = await res.text().catch(() => "");
    throw new Error(`autoiXpert reports/${id} -> HTTP ${res.status} ${text.slice(0, 200)}`);
  }
}
