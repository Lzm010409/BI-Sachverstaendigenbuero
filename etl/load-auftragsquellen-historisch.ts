/**
 * load-auftragsquellen-historisch.ts — importiert fixtures/auftragsquellen_historisch.csv
 * in core.dim_auftragsquelle_historisch (aktenzeichen → Auftragsquelle, Klartext).
 *
 * Deckt die Zeit VOR der zentralen autoiXpert-Pflege ab (autoiXpert-intermediary gibt's
 * erst ab 2026). Der Inhaber pflegt die CSV aus seiner Excel. Voller Sync je Deploy.
 * Trenner ';' oder ','; Kopfzeile + '#'-Zeilen werden übersprungen; Aktenzeichen wird
 * normalisiert (Großschrift, keine Leerzeichen) und gegen ^\d{4}/\d+TG$ geprüft.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, "..", "fixtures", "auftragsquellen_historisch.csv");
const AZ = /^\d{4}\/\d+TG$/;

function parseRows(csv: string): Array<{ aktenzeichen: string; quelle: string }> {
  const out: Array<{ aktenzeichen: string; quelle: string }> = [];
  for (const raw of csv.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const parts = line.split(line.includes(";") ? ";" : ",");
    if (parts.length < 2) continue;
    const az = (parts[0] ?? "").toUpperCase().replace(/\s/g, "");
    const quelle = parts.slice(1).join(" ").trim();
    if (az === "AKTENZEICHEN" || !AZ.test(az) || !quelle) continue;
    out.push({ aktenzeichen: az, quelle });
  }
  return out;
}

async function main(): Promise<void> {
  const rows = parseRows(readFileSync(FILE, "utf8"));
  const pool = makePool();
  try {
    await pool.query("BEGIN");
    await pool.query("TRUNCATE core.dim_auftragsquelle_historisch");
    for (const r of rows) {
      await pool.query(
        "INSERT INTO core.dim_auftragsquelle_historisch (aktenzeichen, quelle) VALUES ($1,$2) ON CONFLICT (aktenzeichen) DO UPDATE SET quelle = EXCLUDED.quelle",
        [r.aktenzeichen, r.quelle],
      );
    }
    await pool.query("COMMIT");
    console.log(`Historische Auftragsquellen geladen: ${rows.length}`);
  } catch (err) {
    await pool.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
