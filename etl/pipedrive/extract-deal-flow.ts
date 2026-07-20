/**
 * extract-deal-flow.ts — LF6 Stufe 2: Stage-Historie je Deal nach
 * raw.pipedrive_deal_changelog.
 *
 * Pipedrive liefert die Feld-Änderungshistorie über
 *   GET /v1/deals/{id}/changelog   (Cursor-Pagination, api_token-Query)
 * Wir speichern das komplette data[]-Array je Deal UNVERÄNDERT als JSONB (raw ist
 * heilig). Die Auswertung (Stage-Segmente, Verweildauer) macht sql/040.
 *
 * Inkrementell: nur Deals holen, deren payload.update_time sich seit dem letzten
 * Changelog-Abzug verändert hat (deal_update_time-Vergleich) oder die noch keine
 * Changelog-Zeile haben. Damit bleibt der Nightly-Lauf günstig (~1 Call je neuem/
 * geändertem Deal). v1-Endpunkt, weil die Changelog-Historie nur dort existiert.
 */
import { makePool } from "../db.js";
import { sanitizeForJsonb } from "./sanitize.js";
import { logRun } from "../sevdesk/run-log.js";

const SOURCE = "pipedrive_deal_changelog";

interface DealRow {
  deal_id: number;
  update_time: string | null;
}

interface ChangelogEntry {
  field_key?: string;
  old_value?: unknown;
  new_value?: unknown;
  time?: string;
  [k: string]: unknown;
}

const BASE = () => {
  const domain = process.env.PIPEDRIVE_COMPANY_DOMAIN;
  const token = process.env.PIPEDRIVE_API_TOKEN;
  if (!domain || !token) {
    throw new Error("Fehlt: PIPEDRIVE_COMPANY_DOMAIN und/oder PIPEDRIVE_API_TOKEN");
  }
  return { url: `https://${domain}.pipedrive.com`, token };
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fetchWithBackoff(target: string, maxRetries = 6): Promise<Response> {
  let attempt = 0;
  for (;;) {
    const res = await fetch(target, { headers: { Accept: "application/json" } });
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
    throw new Error(`Pipedrive ${target.split("?")[0]} -> HTTP ${res.status} ${text.slice(0, 200)}`);
  }
}

/** Holt die komplette Changelog-Historie eines Deals (Cursor-Pagination). */
async function fetchChangelog(dealId: number): Promise<ChangelogEntry[]> {
  const { url, token } = BASE();
  const entries: ChangelogEntry[] = [];
  let cursor: string | null = null;
  do {
    const qs = new URLSearchParams({ api_token: token, limit: "500" });
    if (cursor) qs.set("cursor", cursor);
    const res = await fetchWithBackoff(`${url}/api/v1/deals/${dealId}/changelog?${qs}`);
    const body = (await res.json()) as {
      data: ChangelogEntry[] | null;
      additional_data?: { next_cursor?: string | null };
    };
    for (const e of body.data ?? []) entries.push(e);
    cursor = body.additional_data?.next_cursor ?? null;
  } while (cursor);
  return entries;
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    // Kandidaten: valides Aktenzeichen; neu ODER seit letztem Changelog-Abzug geändert.
    const { rows } = await pool.query<DealRow>(
      `SELECT d.id AS deal_id, (d.payload->>'update_time') AS update_time
         FROM raw.pipedrive_deals d
         LEFT JOIN raw.pipedrive_deal_changelog c ON c.deal_id = d.id
        WHERE upper(regexp_replace(d.payload->>'title','\\s','','g')) ~ '^\\d{4}/\\d+TG$'
          AND (
                c.deal_id IS NULL
             OR c.deal_update_time IS NULL
             OR (d.payload->>'update_time')::timestamptz > c.deal_update_time
          )
        ORDER BY d.id`,
    );

    console.log(`Changelog-Extraktion: ${rows.length} Deals zu holen …`);
    let done = 0;
    let sanitized = 0;
    for (const r of rows) {
      const entries = await fetchChangelog(r.deal_id);
      // NUL/verwaiste Surrogate entfernen — sonst kippt der jsonb-Insert (siehe sanitize.ts).
      const { value, changed } = sanitizeForJsonb(entries);
      if (changed) sanitized++;
      await pool.query(
        `INSERT INTO raw.pipedrive_deal_changelog
           (deal_id, deal_update_time, entry_count, payload, extracted_at)
         VALUES ($1, $2, $3, $4, now())
         ON CONFLICT (deal_id) DO UPDATE
           SET deal_update_time = EXCLUDED.deal_update_time,
               entry_count      = EXCLUDED.entry_count,
               payload          = EXCLUDED.payload,
               extracted_at     = now()`,
        [r.deal_id, r.update_time, value.length, JSON.stringify(value)],
      );
      done++;
      if (done % 50 === 0) console.log(`  … ${done}/${rows.length}`);
    }

    await logRun(pool, SOURCE, "ok", done, sanitized ? `sanitized=${sanitized}` : null);
    console.log(
      `Fertig: ${done} Deals mit Changelog aktualisiert${sanitized ? ` (${sanitized} bereinigt)` : ""}.`,
    );
  } catch (err) {
    await logRun(pool, SOURCE, "error", null, err instanceof Error ? err.message : String(err));
    throw err;
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
