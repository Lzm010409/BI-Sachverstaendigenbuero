-- 044_gutachten_incremental.sql — laufender Gutachten-Feed statt Einmal-Backfill
--
-- Der Fachwerte-Bestand (raw.gutachten_fachwerte) kam bisher NUR aus Backfill-
-- Migrationen (019/022/023/025) → eingefroren, neue Fälle bekamen keine WBW/Restwert/
-- Wertminderung. Der neue ETL etl/gutachten/extract-fachwerte.ts füllt inkrementell
-- nach (autoiXpert-PDF → Text → parse-fachwerte → Upsert).
--
-- Diese Migration: Versuchs-Protokoll (damit Fälle ohne abgelegtes Gutachten nicht
-- bei jedem Deploy neu abgefragt werden) + Abdeckungs-Diagnose.

CREATE TABLE IF NOT EXISTS raw.gutachten_fetch_log (
  aktenzeichen text PRIMARY KEY,
  report_id    text,
  status       text NOT NULL,          -- ok | kein_dokument | kein_report | kein_wert | fehler
  note         text,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE raw.gutachten_fetch_log IS
  'Versuchsprotokoll des Gutachten-Feeds je Aktenzeichen (letzter Stand). Verhindert Dauer-Retries bei Fällen ohne abgelegtes Gutachten.';

-- Abdeckungs-Diagnose: wie vollständig sind die Fachwerte über die won-Fälle?
CREATE OR REPLACE VIEW marts.v_gutachten_abdeckung AS
SELECT
  count(*)                                                        AS won_faelle,
  count(g.aktenzeichen)                                           AS mit_fachwerten,
  count(*) - count(g.aktenzeichen)                                AS ohne_fachwerte,
  round(100.0 * count(g.aktenzeichen) / NULLIF(count(*), 0), 1)   AS abdeckung_pct,
  count(*) FILTER (WHERE l.status = 'kein_dokument')              AS ohne_abgelegtes_gutachten,
  max(g.extracted_at)                                             AS letzte_fachwerte_erfassung
FROM core.fact_durchlauf fd
LEFT JOIN core.fact_gutachten     g USING (aktenzeichen)
LEFT JOIN raw.gutachten_fetch_log l USING (aktenzeichen)
WHERE fd.won_time IS NOT NULL;
