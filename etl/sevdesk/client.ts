/**
 * client.ts — minimaler sevDesk-REST-v1-Client (read-only) für die Extraktion.
 *
 * Auth: read-only API-Token im `Authorization`-Header (sevDesk erwartet den Token
 * direkt, OHNE "Bearer"-Präfix). Läuft im Coolify-Container; my.sevdesk.de ist von
 * dort erreichbar. NUR GET.
 *
 * Pagination: offset/limit über `{ objects: [...] }`. Es wird weiter geblättert,
 * solange eine volle Seite (== limit) zurückkommt. Exponentielles Backoff bei
 * 429/5xx (gleiches Muster wie der Pipedrive-Client).
 *
 * API-Details vor Änderungen gegen die aktuelle sevDesk-Doku prüfen, nie aus dem
 * Gedächtnis.
 */

const PAGE = 100;

/**
 * Fehler eines nicht-wiederholbaren sevDesk-HTTP-Status (4xx). Trägt den Status,
 * damit Aufrufer gezielt reagieren können — z. B. 404 (Rechnung in sevDesk gelöscht)
 * je Objekt überspringen, statt den ganzen Lauf abzubrechen.
 */
export class SevdeskHttpError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "SevdeskHttpError";
    this.status = status;
  }
}

function conf(): { base: string; token: string } {
  const base = process.env.SEVDESK_API_BASE ?? "https://my.sevdesk.de/api/v1";
  const token = process.env.SEVDESK_API_TOKEN;
  if (!token) throw new Error("Fehlt: Umgebungsvariable SEVDESK_API_TOKEN");
  return { base: base.replace(/\/+$/, ""), token };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

interface ListResponse<T> {
  objects: T[] | null;
}

async function fetchWithBackoff(url: string, token: string, maxRetries = 6): Promise<Response> {
  let attempt = 0;
  for (;;) {
    const res = await fetch(url, {
      headers: { Accept: "application/json", Authorization: token },
    });
    if (res.ok) return res;
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
    throw new SevdeskHttpError(
      res.status,
      `sevDesk ${url.split("?")[0]} -> HTTP ${res.status} ${text.slice(0, 200)}`,
    );
  }
}

/**
 * Blättert einen sevDesk-Endpunkt (z. B. "Invoice" oder
 * "Invoice/123/getPositions") per offset/limit komplett durch und ruft `onItem`
 * für jedes Element. `params` sind zusätzliche Query-Parameter (Filter, embed).
 */
export async function paginate<T>(
  path: string,
  params: Record<string, string>,
  onItem: (item: T) => Promise<void>,
): Promise<number> {
  const { base, token } = conf();
  let offset = 0;
  let count = 0;

  for (;;) {
    const qs = new URLSearchParams({ ...params, limit: String(PAGE), offset: String(offset) });
    const res = await fetchWithBackoff(`${base}/${path}?${qs}`, token);
    const body = (await res.json()) as ListResponse<T>;
    const items = body.objects ?? [];

    for (const item of items) {
      await onItem(item);
      count++;
    }

    if (items.length < PAGE) break;
    offset += PAGE;
  }

  return count;
}
