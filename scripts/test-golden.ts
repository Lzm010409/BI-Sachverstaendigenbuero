/**
 * test-golden.ts — assertet core.fact_ausbuchung gegen fixtures/golden-deals.json.
 *
 * READ-ONLY: liest nur, verändert nichts. Kann daher nach jedem ETL-Lauf auch
 * gegen die Produktions-Warehouse laufen (die 20 Golden-Deals existieren dort).
 * Lokal vorher mit scripts/load-golden.ts die Fixtures in raw laden.
 *
 * Exit 0 = alle Erwartungswerte stimmen, sonst != 0.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "../etl/db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE = resolve(__dirname, "..", "fixtures", "golden-deals.json");

interface Erwartet {
  aktenzeichen: string | null;
  deal_value_brutto: number | null;
  enthaltene_mwst: number | null;
  ausgebucht_betrag: number | null;
  ausgebucht_grund_id: number | null;
  ist_erfasst: boolean;
  status: string | null;
  org_id: number | null;
  sevdesk_rechnung_id: string | null;
}
interface Golden {
  deal_id: number;
  case: string;
  erwartet_kandidat: Erwartet;
}

/** null-sichere, typ-tolerante Gleichheit (numeric kommt als string aus pg). */
function eq(actual: unknown, expected: unknown): boolean {
  if (expected === null) return actual === null || actual === undefined;
  if (typeof expected === "number") return Number(actual) === expected;
  if (typeof expected === "boolean") return actual === expected;
  return String(actual) === String(expected);
}

async function main(): Promise<void> {
  const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { deals: Golden[] };
  const pool = makePool();
  let failed = 0;
  const fields: (keyof Erwartet)[] = [
    "aktenzeichen", "deal_value_brutto", "enthaltene_mwst", "ausgebucht_betrag",
    "ausgebucht_grund_id", "ist_erfasst", "status", "org_id", "sevdesk_rechnung_id",
  ];

  try {
    for (const g of fixture.deals) {
      const r = await pool.query(
        "SELECT * FROM core.fact_ausbuchung WHERE deal_id = $1",
        [g.deal_id],
      );
      if (r.rowCount !== 1) {
        console.error(`✗ Deal ${g.deal_id} (${g.case}): ${r.rowCount} Zeilen in fact_ausbuchung (erwartet 1)`);
        failed++;
        continue;
      }
      const row = r.rows[0] as Record<string, unknown>;
      const diffs: string[] = [];
      for (const f of fields) {
        if (!eq(row[f], g.erwartet_kandidat[f])) {
          diffs.push(`${f}: ist=${JSON.stringify(row[f])} erwartet=${JSON.stringify(g.erwartet_kandidat[f])}`);
        }
      }
      if (diffs.length) {
        console.error(`✗ Deal ${g.deal_id} (${g.case}):\n    ${diffs.join("\n    ")}`);
        failed++;
      }
    }

    const total = fixture.deals.length;
    if (failed === 0) {
      console.log(`✓ Golden-Test grün: ${total}/${total} Deals stimmen.`);
    } else {
      console.error(`\n✗ Golden-Test: ${failed}/${total} Deals abweichend.`);
      process.exitCode = 1;
    }
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
