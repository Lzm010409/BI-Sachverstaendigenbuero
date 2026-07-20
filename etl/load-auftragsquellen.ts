/**
 * load-auftragsquellen.ts — spiegelt fixtures/auftragsquellen.json (labels) in
 * core.dim_auftragsquelle_label. Quelle der Wahrheit = die Datei. Voller Sync je
 * Deploy. Der Inhaber pflegt die Klartext-Namen der Auftragsquellen dort.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, "..", "fixtures", "auftragsquellen.json");

async function main(): Promise<void> {
  const { labels } = JSON.parse(readFileSync(FILE, "utf8")) as { labels: Record<string, string> };
  const entries = Object.entries(labels ?? {});
  const pool = makePool();
  try {
    await pool.query("BEGIN");
    await pool.query("TRUNCATE core.dim_auftragsquelle_label");
    for (const [contactId, label] of entries) {
      if (!contactId || !label) continue;
      await pool.query(
        "INSERT INTO core.dim_auftragsquelle_label (contact_id, label) VALUES ($1, $2) ON CONFLICT (contact_id) DO UPDATE SET label = EXCLUDED.label",
        [contactId, label],
      );
    }
    await pool.query("COMMIT");
    console.log(`Auftragsquellen-Labels geladen: ${entries.length}`);
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
