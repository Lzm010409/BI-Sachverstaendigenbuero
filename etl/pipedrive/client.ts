/**
 * client.ts — minimaler Pipedrive-REST-v2-Client für die Extraktion.
 *
 * Auth: read-only API-Token (`api_token`-Query-Parameter). Läuft im Coolify-
 * Container; api.pipedrive.com ist von dort erreichbar.
 *
 * v2-Parameter (gegen aktuelle Doku geprüft, 2026-07):
 *   limit<=500, cursor (opak), updated_since (RFC3339), sort_by=update_time,
 *   include_option_labels=true (Enum-Werte als {id,label}).
 * Cursor-Pagination vollständig; exponentielles Backoff bei 429/5xx.
 */

const BASE = () => {
  const domain = process.env.PIPEDRIVE_COMPANY_DOMAIN;
  const token = process.env.PIPEDRIVE_API_TOKEN;
  if (!domain || !token) {
    throw new Error(
      "Fehlt: PIPEDRIVE_COMPANY_DOMAIN und/oder PIPEDRIVE_API_TOKEN",
    );
  }
  return { url: `https://${domain}.pipedrive.com`, token };
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Formatiert einen Zeitpunkt für Pipedrive v2 `updated_since`. Pipedrive validiert
 * RFC3339 OHNE Millisekunden (z. B. 2025-01-01T10:20:00Z); `Date.toISOString()`
 * liefert aber `…:00.000Z`. Seit ~15.07.2026 lehnt Pipedrive das mit HTTP 400
 * ("updated_since: This value is not a valid datetime") ab — dadurch fror die
 * inkrementelle Extraktion ein. Millisekunden also entfernen.
 */
export function toUpdatedSince(since: string | Date): string {
  return new Date(since).toISOString().replace(/\.\d{3}Z$/, "Z");
}

interface PageResponse<T> {
  success: boolean;
  data: T[] | null;
  additional_data?: { next_cursor?: string | null };
}

/**
 * Läuft eine v2-Collection (z. B. "deals", "organizations") per Cursor komplett
 * durch und ruft `onItem` für jedes Element. Gibt die höchste update_time zurück.
 */
export async function paginate<T extends { update_time?: string }>(
  resource: "deals" | "organizations" | "persons",
  params: Record<string, string>,
  onItem: (item: T) => Promise<void>,
): Promise<{ count: number; maxUpdateTime: string | null }> {
  const { url, token } = BASE();
  let cursor: string | null = null;
  let count = 0;
  let maxUpdateTime: string | null = null;

  do {
    const qs = new URLSearchParams({
      api_token: token,
      limit: "500",
      ...params,
    });
    if (cursor) qs.set("cursor", cursor);

    const res = await fetchWithBackoff(`${url}/api/v2/${resource}?${qs}`);
    const body = (await res.json()) as PageResponse<T>;

    for (const item of body.data ?? []) {
      await onItem(item);
      count++;
      const ut = item.update_time;
      if (ut && (maxUpdateTime === null || ut > maxUpdateTime)) maxUpdateTime = ut;
    }
    cursor = body.additional_data?.next_cursor ?? null;
  } while (cursor);

  return { count, maxUpdateTime };
}

async function fetchWithBackoff(target: string, maxRetries = 6): Promise<Response> {
  let attempt = 0;
  for (;;) {
    const res = await fetch(target, { headers: { Accept: "application/json" } });
    if (res.ok) return res;
    // 429 / 5xx -> Backoff; Rate-Limit ggf. via Retry-After.
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
    throw new Error(`Pipedrive ${target.split("?")[0]} -> HTTP ${res.status} ${text.slice(0, 200)}`);
  }
}
