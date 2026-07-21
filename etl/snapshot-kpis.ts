/**
 * snapshot-kpis.ts — schreibt die aktuellen Headline-KPIs monatlich nach
 * core.kpi_snapshot (Kennzahlen-Verläufe). Idempotenter Upsert je Monat: läuft am
 * Ende der nächtlichen ETL-Kette, aktualisiert die Zeile des laufenden Monats.
 *
 * Alle KPI-Definitionen leben in marts.v_kpi_aktuell (sql/061) — hier keine Fachlogik,
 * nur das Wegschreiben. Neue KPI ergänzt man in v_kpi_aktuell, nicht hier.
 */
import { makePool } from "./db.js";
import { logRun } from "./sevdesk/run-log.js";

const SOURCE = "kpi_snapshot";

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const res = await pool.query(
      `INSERT INTO core.kpi_snapshot (snapshot_monat, kpi_key, wert)
         SELECT date_trunc('month', now())::date, kpi_key, wert
           FROM marts.v_kpi_aktuell
       ON CONFLICT (snapshot_monat, kpi_key)
         DO UPDATE SET wert = EXCLUDED.wert, erfasst_at = now()`,
    );
    await logRun(pool, SOURCE, "ok", res.rowCount ?? null, null);
    console.log(`KPI-Snapshot geschrieben: ${res.rowCount} Kennzahlen (Monat ${new Date().toISOString().slice(0, 7)})`);
  } catch (err) {
    await logRun(pool, SOURCE, "error", null, err instanceof Error ? err.message : String(err));
    throw err;
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
