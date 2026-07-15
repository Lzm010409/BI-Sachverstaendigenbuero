/**
 * extract-organizations.ts — Organisationen nach raw.pipedrive_organizations.
 * Für dim_organisation (Name + Typ aus label_ids: 35=Versicherer, 32=Auftraggeber).
 * Analog zu extract-deals.ts.
 */
import { makePool } from "../db.js";
import { paginate } from "./client.js";

const SOURCE = "pipedrive_organizations";

interface Org {
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
    };
    if (since) params.updated_since = new Date(since).toISOString();

    console.log(
      `Extrahiere Organisationen${since ? ` seit ${params.updated_since}` : " (voll)"} …`,
    );

    const { count, maxUpdateTime } = await paginate<Org>(
      "organizations",
      params,
      async (org) => {
        await pool.query(
          `INSERT INTO raw.pipedrive_organizations (id, payload, extracted_at)
             VALUES ($1, $2, now())
           ON CONFLICT (id) DO UPDATE
             SET payload = EXCLUDED.payload, extracted_at = now()`,
          [org.id, org],
        );
      },
    );

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

    console.log(`Fertig: ${count} Organisationen. Wasserstand: ${newWm ?? "—"}`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
