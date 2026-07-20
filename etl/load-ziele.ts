/**
 * load-ziele.ts — spiegelt fixtures/ziele.json in core.dim_ziele.
 * Quelle der Wahrheit = die Datei. Voller Sync (TRUNCATE + INSERT) je Deploy, damit
 * geänderte/entfernte Ziele sauber übernommen werden. Keine Personenbezugsdaten.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, "..", "fixtures", "ziele.json");

interface Ziel {
  kennzahl: string;
  label: string;
  ziel: number;
  richtung: string;
  ord?: number;
}

async function main(): Promise<void> {
  const { ziele } = JSON.parse(readFileSync(FILE, "utf8")) as { ziele: Ziel[] };
  const pool = makePool();
  try {
    await pool.query("BEGIN");
    await pool.query("TRUNCATE core.dim_ziele");
    for (const z of ziele) {
      await pool.query(
        "INSERT INTO core.dim_ziele (kennzahl, label, ziel, richtung, ord) VALUES ($1,$2,$3,$4,$5)",
        [z.kennzahl, z.label, z.ziel, z.richtung, z.ord ?? 0],
      );
    }
    await pool.query("COMMIT");
    console.log(`Zielwerte geladen: ${ziele.length}`);
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
