/**
 * db.ts — gemeinsamer Postgres-Pool für ETL-Jobs. Verbindung/Rolle `etl` aus
 * der Umgebung (siehe .env.example).
 */
import pg from "pg";

function env(name: string, fallback?: string): string {
  const v = process.env[name] ?? fallback;
  if (v === undefined) {
    throw new Error(`Fehlt: Umgebungsvariable ${name}`);
  }
  return v;
}

export function makePool(): pg.Pool {
  return new pg.Pool({
    host: env("WAREHOUSE_DB_HOST"),
    port: Number(env("WAREHOUSE_DB_PORT", "5432")),
    database: env("WAREHOUSE_DB_NAME", "warehouse"),
    user: env("ETL_DB_USER", "etl"),
    password: env("ETL_DB_PASSWORD"),
  });
}
