/**
 * extract-deleted-deals.ts — Grabstein-Log der in Pipedrive GELÖSCHTEN Deals.
 *
 * Der reguläre Deal-Import (extract-deals.ts) liefert nur nicht-gelöschte Deals und
 * löscht nie. Ein nach dem Import gelöschter Deal bliebe daher als Karteileiche in
 * raw.pipedrive_deals. Dieser Job fragt `GET /api/v2/deals?status=deleted` ab
 * (rollendes 30-Tage-Fenster) und schreibt die IDs dauerhaft nach
 * raw.pipedrive_deal_deleted. Die Fakten (fact_ausbuchung, fact_durchlauf) schließen
 * diese IDs aus. raw.pipedrive_deals selbst bleibt unangetastet ("Rohdaten heilig").
 *
 * Kein Wasserstand: das Fenster ist klein, wir holen es voll und akkumulieren per
 * Upsert (Grabsteine bleiben, auch wenn Pipedrive sie nach 30 Tagen nicht mehr meldet).
 */
import { makePool } from "../db.js";
import { paginate } from "./client.js";
import { sanitizeForJsonb } from "./sanitize.js";
import { logRun } from "../sevdesk/run-log.js";

const SOURCE = "pipedrive_deals_deleted";

interface Deal {
  id: number;
  update_time?: string;
  [k: string]: unknown;
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const params: Record<string, string> = {
      status: "deleted",
      sort_by: "update_time",
      sort_direction: "asc",
    };
    console.log("Extrahiere gelöschte Deals (status=deleted) …");

    let sanitized = 0;
    const { count } = await paginate<Deal>("deals", params, async (deal) => {
      const { value, changed } = sanitizeForJsonb(deal);
      if (changed) sanitized++;
      await pool.query(
        `INSERT INTO raw.pipedrive_deal_deleted (id, payload, extracted_at)
           VALUES ($1, $2, now())
         ON CONFLICT (id) DO UPDATE
           SET payload = EXCLUDED.payload`, // extracted_at bleibt = erstmals erkannt
        [value.id, value],
      );
    });

    await logRun(pool, SOURCE, "ok", count, sanitized ? `sanitized=${sanitized}` : null);
    console.log(`Fertig: ${count} gelöschte Deals im Grabstein-Log.`);
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
