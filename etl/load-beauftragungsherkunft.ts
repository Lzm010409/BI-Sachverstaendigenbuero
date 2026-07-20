/**
 * load-beauftragungsherkunft.ts — importiert fixtures/beauftragungsherkunft.csv
 * in core.dim_beauftragungsherkunft (person_id → Kanal, Klartext-Kategorie).
 *
 * Kanäle: WERKSTATT, INTERNET, DRITTE, RECHTSANWALT. Die Zuordnung stammt aus der
 * Inhaber-Liste, per Namensabgleich auf die pseudonyme Pipedrive-person_id gelöst
 * (kein Klarname im Warehouse). Voller Sync je Deploy (TRUNCATE + Insert).
 * Trenner ';' oder ','; Kopfzeile + '#'-Zeilen werden übersprungen.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, "..", "fixtures", "beauftragungsherkunft.csv");
const VALID = new Set(["WERKSTATT", "INTERNET", "DRITTE", "RECHTSANWALT"]);

function parseRows(csv: string): Array<{ person_id: number; kategorie: string }> {
  const out: Array<{ person_id: number; kategorie: string }> = [];
  for (const raw of csv.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const parts = line.split(line.includes(";") ? ";" : ",");
    if (parts.length < 2) continue;
    const idRaw = (parts[0] ?? "").trim();
    const kategorie = (parts[1] ?? "").trim().toUpperCase();
    if (idRaw.toLowerCase() === "person_id") continue; // Kopfzeile
    const person_id = Number(idRaw);
    if (!Number.isInteger(person_id) || person_id <= 0) continue;
    if (!VALID.has(kategorie)) continue;
    out.push({ person_id, kategorie });
  }
  return out;
}

async function main(): Promise<void> {
  const rows = parseRows(readFileSync(FILE, "utf8"));
  const pool = makePool();
  try {
    await pool.query("BEGIN");
    await pool.query("TRUNCATE core.dim_beauftragungsherkunft");
    for (const r of rows) {
      await pool.query(
        "INSERT INTO core.dim_beauftragungsherkunft (person_id, kategorie) VALUES ($1,$2) ON CONFLICT (person_id) DO UPDATE SET kategorie = EXCLUDED.kategorie",
        [r.person_id, r.kategorie],
      );
    }
    await pool.query("COMMIT");
    console.log(`Beauftragungsherkunft geladen: ${rows.length} Personen`);
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
