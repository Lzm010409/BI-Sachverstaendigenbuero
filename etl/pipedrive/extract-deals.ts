/**
 * extract-deals.ts — inkrementelle Extraktion aller Deals nach raw.pipedrive_deals.
 *
 * - Wasserstand in raw._sync_state (source='pipedrive_deals').
 * - Kein status-Filter -> open + won + lost. (Archivierte prüfen wir beim ersten
 *   Live-Lauf; v2 liefert is_archived im Payload.)
 * - sort_by=update_time asc, damit der Wasserstand monoton wächst; Abbruch ist
 *   unkritisch, da Upsert idempotent ist und vom alten Wasserstand neu startet.
 * - Rohantwort unverändert als JSONB.
 */
import { makePool } from "../db.js";
import { paginate } from "./client.js";

const SOURCE = "pipedrive_deals";

interface Deal {
  id: number;
  update_time?: string;
  [k: string]: unknown;
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const wm = await pool.query<{ last_updated_ts: string | null }>(
      "SELECT last_updated_ts FROM raw._sync_state WHERE source = $1",
      [SOURCE],
    );
    const since = wm.rows[0]?.last_updated_ts ?? null;

    const params: Record<string, string> = {
      sort_by: "update_time",
      sort_direction: "asc",
      include_option_labels: "true",
    };
    if (since) params.updated_since = new Date(since).toISOString();

    console.log(
      `Extrahiere Deals${since ? ` seit ${params.updated_since}` : " (voll)"} …`,
    );

    const { count, maxUpdateTime } = await paginate<Deal>(
      "deals",
      params,
      async (deal) => {
        await pool.query(
          `INSERT INTO raw.pipedrive_deals (id, payload, extracted_at)
             VALUES ($1, $2, now())
           ON CONFLICT (id) DO UPDATE
             SET payload = EXCLUDED.payload, extracted_at = now()`,
          [deal.id, deal],
        );
      },
    );

    // Wasserstand nur vorrücken, nie zurück.
    const newWm = maxUpdateTime ?? since;
    await pool.query(
      `INSERT INTO raw._sync_state (source, last_updated_ts, last_run)
         VALUES ($1, $2, now())
       ON CONFLICT (source) DO UPDATE
         SET last_updated_ts = GREATEST(
               raw._sync_state.last_updated_ts, EXCLUDED.last_updated_ts),
             last_run = now()`,
      [SOURCE, newWm],
    );

    console.log(`Fertig: ${count} Deals aktualisiert. Wasserstand: ${newWm ?? "—"}`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
