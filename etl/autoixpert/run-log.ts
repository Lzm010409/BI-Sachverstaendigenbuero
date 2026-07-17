/**
 * run-log.ts — schreibt ein Extraktions-Ergebnis nach core._etl_run.
 * Observability darf den Lauf nie kippen: Fehler beim Loggen werden geschluckt.
 * (Identisch zum sevDesk-Pendant; jeder Quell-Ordner bleibt self-contained.)
 */
import type pg from "pg";

export async function logRun(
  pool: pg.Pool,
  source: string,
  status: "ok" | "error",
  rows: number | null,
  error: string | null,
): Promise<void> {
  try {
    await pool.query(
      "INSERT INTO core._etl_run (source, status, rows, error) VALUES ($1, $2, $3, $4)",
      [source, status, rows, error ? error.slice(0, 500) : null],
    );
  } catch {
    /* absichtlich ignoriert */
  }
}
