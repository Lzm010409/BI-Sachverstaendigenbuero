-- 062_kpi_backfill_historie.sql — historische KPI-Snapshots rückwirkend erzeugen
--
-- Für die REKONSTRUIERBAREN Kennzahlen liegt der Verlauf in den datierten Quelldaten
-- (won_time = Ausbuchungsdatum, add_time = Fallanlage). Diese werden hier je Monatsende
-- rückwirkend als Snapshot geschrieben — so beginnt die Historie mit der Datenbasis
-- (ab Okt 2024) statt erst mit dem ersten Live-Lauf.
--
-- BEWUSST NICHT rückgerechnet: die Abdeckungs-/Qualitäts-KPIs (versicherer_/herkunft_/
-- gutachten_/kuerzungsgrund_abdeckung). Sie messen, wie vollständig HEUTE die Daten
-- sind; aus den bereits nachgezogenen Altdaten rekonstruiert ergäbe jede Vergangenheits-
-- zahl ~den heutigen Wert — eine flache, irreführende Linie. Sie starten ehrlich ab
-- dem ersten Live-Lauf (sql/061).
--
-- Jede KPI ist mit ihrer LIVE-Definition (v_kpi_aktuell) konsistent, nur mit Datums-
-- schnitt auf den Monatsletzten (< Monatserster des Folgemonats). Idempotent
-- (ON CONFLICT DO UPDATE) — der laufende Monat wird ohnehin vom nächtlichen Job
-- überschrieben. Einmalig via _migrations (nicht bei jedem Deploy).

INSERT INTO core.kpi_snapshot (snapshot_monat, kpi_key, wert)
WITH grenzen AS (
  SELECT date_trunc('month', min(add_time))::date AS von,
         date_trunc('month', now())::date          AS bis_monat
  FROM core.fact_ausbuchung
),
monate AS (
  SELECT gs::date AS m, (gs + interval '1 month')::date AS bis
  FROM grenzen, generate_series(von, bis_monat, interval '1 month') gs
),
-- Kürzung/Ausbuchung je Fall (wie v_durchsetzung_echt, sql/028) — datierbar über won_time.
kuerzung AS (
  SELECT aktenzeichen, sum(kuerzungsbetrag) AS kuerzung
  FROM core.fact_kuerzungsereignis WHERE kuerzungsbetrag > 0 GROUP BY aktenzeichen
),
verlust_fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen
)
SELECT mo.m, k.kpi_key, k.wert
FROM monate mo
CROSS JOIN LATERAL (
  VALUES
    -- Won-Fälle kumuliert (bis Monatsende abgeschlossen)
    ('won_faelle_kum',
      (SELECT count(*)::numeric FROM core.fact_ausbuchung fa
        WHERE fa.won_time IS NOT NULL AND fa.won_time < mo.bis)),
    -- Umsatz brutto kumuliert (Summe deal_value_brutto der bis dahin won-Fälle)
    ('umsatz_brutto_kum',
      (SELECT round(sum(fa.deal_value_brutto)) FROM core.fact_ausbuchung fa
        WHERE fa.won_time IS NOT NULL AND fa.won_time < mo.bis)),
    -- Forderungsverlust kumuliert (nur erfasste Ausbuchungen > 0; null ≠ 0)
    ('forderungsverlust_kum',
      (SELECT round(sum(fa.ausgebucht_betrag)) FROM core.fact_ausbuchung fa
        WHERE fa.won_time IS NOT NULL AND fa.won_time < mo.bis AND fa.ausgebucht_betrag > 0)),
    -- Offene Fälle (Bestand): angelegt, aber bis Monatsende weder won noch lost
    ('offene_faelle',
      (SELECT count(*)::numeric FROM core.fact_ausbuchung fa
        WHERE fa.add_time < mo.bis
          AND (fa.won_time IS NULL OR fa.won_time >= mo.bis)
          AND fa.status <> 'lost')),
    -- Durchsetzungsquote (echt), Stand Monatsende — identische Logik wie v_durchsetzung_echt
    ('durchsetzung_pct',
      (SELECT round(100.0*(1 - sum(COALESCE(a.ausbuchung,0)) / NULLIF(sum(k.kuerzung),0)),1)
         FROM kuerzung k
         JOIN core.fact_ausbuchung fa
           ON fa.aktenzeichen = k.aktenzeichen AND fa.won_time IS NOT NULL AND fa.won_time < mo.bis
         LEFT JOIN verlust_fv a ON a.aktenzeichen = k.aktenzeichen))
) AS k(kpi_key, wert)
WHERE k.wert IS NOT NULL
ON CONFLICT (snapshot_monat, kpi_key) DO UPDATE
  SET wert = EXCLUDED.wert, erfasst_at = now();
