/**
 * load-kategorien.ts — spiegelt fixtures/positionskategorie.json in
 * core.dim_positionskategorie_regel (Quelle der Wahrheit = die Datei).
 *
 * Laeuft bei jedem Deploy. Voller Sync in einer Transaktion (TRUNCATE + INSERT),
 * damit die Datei massgeblich bleibt und entfernte Regeln auch verschwinden.
 * Read-only-Quelle (Repo-Datei); keine Personenbezugsdaten.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "../db.js";
import { logRun } from "./run-log.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, "..", "..", "fixtures", "positionskategorie.json");

interface Regel {
  muster: string;
  kategorie: string;
  prioritaet?: number;
}

async function main(): Promise<void> {
  const { regeln } = JSON.parse(readFileSync(FILE, "utf8")) as { regeln: Regel[] };
  const pool = makePool();
  try {
    await pool.query("BEGIN");
    await pool.query("TRUNCATE core.dim_positionskategorie_regel");
    for (const r of regeln) {
      await pool.query(
        "INSERT INTO core.dim_positionskategorie_regel (muster, kategorie, prioritaet) VALUES ($1, $2, $3)",
        [r.muster, r.kategorie, r.prioritaet ?? 100],
      );
    }
    await pool.query("COMMIT");
    await logRun(pool, "kategorien_regeln", "ok", regeln.length, null);
    console.log(`Kategorien-Regeln geladen: ${regeln.length}`);
  } catch (err) {
    await pool.query("ROLLBACK").catch(() => {});
    await logRun(pool, "kategorien_regeln", "error", null, err instanceof Error ? err.message : String(err));
    throw err;
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
