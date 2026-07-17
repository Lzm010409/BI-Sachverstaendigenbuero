-- 034_durchsetzung_zahlung_perf.sql — v_durchsetzung_zahlung beschleunigen
--
-- v_durchsetzung_zahlung brauchte ~39s: der Join per_az → core.fact_ausbuchung
-- (Aktenzeichen aus regexp über raw, kein Index) wurde als Nested Loop pro Zeile neu
-- ausgewertet. Fix: fact_ausbuchung EINMAL in einer MATERIALIZED-CTE berechnen →
-- ~2s, identisches Ergebnis. Gleiche Spalten (CREATE OR REPLACE-kompatibel); die
-- abgeleiteten Views (je Versicherer/Anwalt/Grund, _grund) erben den Speedup.

CREATE OR REPLACE VIEW marts.v_durchsetzung_zahlung AS
WITH per_az AS (
  SELECT
    aktenzeichen,
    sum(rechnung_brutto)            AS rechnung_brutto,
    sum(erste_zahlung)              AS erste_zahlung,
    sum(gezahlt_gesamt)             AS gezahlt_gesamt,
    sum(ausgebucht)                 AS ausgebucht,
    sum(kuerzung)                   AS kuerzung,
    bool_and(ist_mwst_einbehalt)    AS ist_mwst_einbehalt,
    min(erste_zahlung_datum)        AS erste_zahlung_datum
  FROM core.fact_rechnung_zahlung
  WHERE aktenzeichen IS NOT NULL AND erste_zahlung IS NOT NULL
  GROUP BY aktenzeichen
),
fa AS MATERIALIZED (
  SELECT aktenzeichen, org_id, anwalt_org_id, ausgebucht_grund_id
  FROM core.fact_ausbuchung
  WHERE won_time IS NOT NULL
)
SELECT
  p.aktenzeichen,
  COALESCE(NULLIF(trim(vo.name), ''), '(unbekannt)') AS versicherer,
  aw.name                                            AS anwalt,
  COALESCE(g.grund, '(offen)')                       AS kuerzungsgrund,
  p.rechnung_brutto,
  p.erste_zahlung,
  p.gezahlt_gesamt,
  p.ausgebucht,
  p.kuerzung,
  p.kuerzung - p.ausgebucht                          AS durchgesetzt,
  round(1 - p.ausgebucht / NULLIF(p.kuerzung, 0), 4) AS durchsetzungsquote,
  p.erste_zahlung_datum
FROM per_az p
JOIN fa                          ON fa.aktenzeichen = p.aktenzeichen
LEFT JOIN core.dim_organisation vo ON vo.org_id = fa.org_id AND vo.typ = 'versicherer'
LEFT JOIN core.dim_organisation aw ON aw.org_id = fa.anwalt_org_id
LEFT JOIN core.dim_ausbuchungsgrund g ON g.grund_id = fa.ausgebucht_grund_id
WHERE p.kuerzung > 1
  AND NOT p.ist_mwst_einbehalt
  AND COALESCE(fa.ausgebucht_grund_id, 0) <> 71;
