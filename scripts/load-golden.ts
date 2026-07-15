/**
 * load-golden.ts — lädt die Golden-Fixtures in raw.pipedrive_deals.
 *
 * NUR für lokale Entwicklung/Tests (leert raw.pipedrive_deals vorher!). In
 * Produktion füllt der Extraktor raw; dort nicht ausführen.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "../etl/db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE = resolve(__dirname, "..", "fixtures", "golden-deals.json");

interface Golden { deal_id: number; raw: unknown }

async function main(): Promise<void> {
  if (process.env.ALLOW_LOAD_GOLDEN !== "1") {
    throw new Error("Schutz: ALLOW_LOAD_GOLDEN=1 setzen (leert raw.pipedrive_deals — nur lokal!).");
  }
  const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { deals: Golden[] };
  const pool = makePool();
  try {
    await pool.query("TRUNCATE raw.pipedrive_deals");
    for (const g of fixture.deals) {
      await pool.query(
        "INSERT INTO raw.pipedrive_deals (id, payload, extracted_at) VALUES ($1, $2, now())",
        [g.deal_id, g.raw],
      );
    }
    console.log(`Geladen: ${fixture.deals.length} Golden-Deals in raw.pipedrive_deals.`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
