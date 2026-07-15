/**
 * load-sevdesk.ts — lädt das sevDesk-Sample in raw.sevdesk_invoices /
 * raw.sevdesk_invoice_positions.
 *
 * NUR für lokale Entwicklung/Tests (leert beide Tabellen vorher!). In Produktion
 * füllt der Extraktor raw; dort nicht ausführen.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "../etl/db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE = resolve(__dirname, "..", "fixtures", "sevdesk-sample.json");

interface Fixture {
  invoices: { id: number; raw: unknown }[];
  positions: { id: number; invoice_id: number; raw: unknown }[];
}

async function main(): Promise<void> {
  if (process.env.ALLOW_LOAD_GOLDEN !== "1") {
    throw new Error("Schutz: ALLOW_LOAD_GOLDEN=1 setzen (leert raw.sevdesk_* — nur lokal!).");
  }
  const fx = JSON.parse(readFileSync(FIXTURE, "utf8")) as Fixture;
  const pool = makePool();
  try {
    await pool.query("TRUNCATE raw.sevdesk_invoice_positions, raw.sevdesk_invoices");
    for (const inv of fx.invoices) {
      await pool.query(
        "INSERT INTO raw.sevdesk_invoices (id, payload, extracted_at) VALUES ($1, $2, now())",
        [inv.id, inv.raw],
      );
    }
    for (const p of fx.positions) {
      await pool.query(
        "INSERT INTO raw.sevdesk_invoice_positions (id, invoice_id, payload, extracted_at) VALUES ($1, $2, $3, now())",
        [p.id, p.invoice_id, p.raw],
      );
    }
    console.log(`Geladen: ${fx.invoices.length} Rechnung(en), ${fx.positions.length} Positionen.`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
