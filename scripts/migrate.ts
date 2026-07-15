/**
 * migrate.ts — Migrations-Runner
 *
 * Wendet nummerierte SQL-Dateien aus sql/ genau einmal an. Zustand in
 * _meta._migrations. Läuft beim Deploy (migrate-Service), exit 0 bei Erfolg.
 *
 * Eigenschaften:
 *  - numerisch sortiert (001, 002, …)
 *  - jede Datei in EINER Transaktion; Fehler -> Rollback, exit 1
 *  - idempotent: bereits angewandte Dateien werden übersprungen
 *  - Drift-Schutz: ändert sich der Inhalt einer bereits angewandten Datei
 *    (Checksum weicht ab) -> Abbruch, damit Semantik nicht still verschoben wird
 *
 * Verbindung + Rolle `etl` aus der Umgebung (siehe .env.example).
 */

import { readFileSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import pg from "pg";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SQL_DIR = resolve(__dirname, "..", "sql");

function env(name: string, fallback?: string): string {
  const v = process.env[name] ?? fallback;
  if (v === undefined) {
    console.error(`Fehlt: Umgebungsvariable ${name}`);
    process.exit(1);
  }
  return v;
}

function sha256(s: string): string {
  return createHash("sha256").update(s, "utf8").digest("hex");
}

/** Nur Dateien wie 001_*.sql, numerisch nach dem führenden Präfix sortiert. */
function migrationFiles(): string[] {
  return readdirSync(SQL_DIR)
    .filter((f) => /^\d+.*\.sql$/.test(f))
    .sort((a, b) => {
      const na = parseInt(a, 10);
      const nb = parseInt(b, 10);
      return na === nb ? a.localeCompare(b) : na - nb;
    });
}

async function main(): Promise<void> {
  const client = new pg.Client({
    host: env("WAREHOUSE_DB_HOST"),
    port: Number(env("WAREHOUSE_DB_PORT", "5432")),
    database: env("WAREHOUSE_DB_NAME", "warehouse"),
    user: env("ETL_DB_USER", "etl"),
    password: env("ETL_DB_PASSWORD"),
  });
  await client.connect();

  try {
    await client.query("CREATE SCHEMA IF NOT EXISTS _meta");
    await client.query(`
      CREATE TABLE IF NOT EXISTS _meta._migrations (
        filename   text PRIMARY KEY,
        checksum   text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      )
    `);

    const applied = new Map<string, string>();
    const rows = await client.query<{ filename: string; checksum: string }>(
      "SELECT filename, checksum FROM _meta._migrations",
    );
    for (const r of rows.rows) applied.set(r.filename, r.checksum);

    const files = migrationFiles();
    let ran = 0;

    for (const file of files) {
      const sql = readFileSync(join(SQL_DIR, file), "utf8");
      const checksum = sha256(sql);
      const prev = applied.get(file);

      if (prev !== undefined) {
        if (prev !== checksum) {
          throw new Error(
            `Drift: ${file} wurde nach dem Anwenden verändert ` +
              `(Checksum ${prev.slice(0, 12)} != ${checksum.slice(0, 12)}). ` +
              `Migrationen sind unveränderlich — neue Datei anlegen statt editieren.`,
          );
        }
        continue; // schon angewandt, unverändert
      }

      process.stdout.write(`anwenden: ${file} … `);
      try {
        await client.query("BEGIN");
        await client.query(sql);
        await client.query(
          "INSERT INTO _meta._migrations (filename, checksum) VALUES ($1, $2)",
          [file, checksum],
        );
        await client.query("COMMIT");
        ran++;
        console.log("ok");
      } catch (err) {
        await client.query("ROLLBACK");
        throw err;
      }
    }

    console.log(
      ran === 0
        ? "Keine neuen Migrationen."
        : `${ran} Migration(en) angewandt.`,
    );
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
