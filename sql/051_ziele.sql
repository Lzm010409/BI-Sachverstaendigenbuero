-- 051_ziele.sql — editierbare Zielwerte (Soll-Ist im Management-Cockpit)
--
-- Zielwerte kommen aus fixtures/ziele.json (Loader etl/load-ziele.ts → dim_ziele).
-- Ändern = Zahl in der JSON anpassen, nächster Deploy übernimmt es. Diese Migration
-- legt die Tabelle + die Soll-Ist-View an; die View rechnet die Ist-Werte live und
-- verbindet sie mit den Zielen.

CREATE TABLE IF NOT EXISTS core.dim_ziele (
  kennzahl text PRIMARY KEY,          -- durchsetzung | umsatz | durchlaufzeit | konformitaet
  label    text NOT NULL,
  ziel     numeric NOT NULL,
  richtung text NOT NULL,             -- 'hoch' = höher besser, 'niedrig' = niedriger besser
  ord      int NOT NULL DEFAULT 0
);
COMMENT ON TABLE core.dim_ziele IS
  'Zielwerte für Soll-Ist (Management-Cockpit). Quelle: fixtures/ziele.json via load-ziele.ts.';

CREATE OR REPLACE VIEW marts.v_ziele_soll_ist AS
WITH ist(kennzahl, ist) AS (
  SELECT 'durchsetzung',
         (SELECT round(100*(1-sum(ausgebucht)/NULLIF(sum(kuerzung),0)),1) FROM marts.v_durchsetzung_zahlung)
  UNION ALL SELECT 'umsatz',
         (SELECT round(sum(deal_value_brutto)) FROM core.fact_ausbuchung
            WHERE won_time >= date_trunc('month',now())-interval '1 month' AND won_time < date_trunc('month',now()))
  UNION ALL SELECT 'durchlaufzeit',
         (SELECT median_tage FROM marts.v_durchlaufzeit)
  UNION ALL SELECT 'konformitaet',
         (SELECT round(100.0*count(*) FILTER (WHERE befund='konform')/NULLIF(count(*),0),1) FROM marts.v_honorar_konformitaet)
)
SELECT
  z.label                                                                   AS kennzahl,
  i.ist                                                                     AS ist,
  z.ziel                                                                    AS ziel,
  CASE WHEN z.richtung='hoch' THEN round(100.0*i.ist/NULLIF(z.ziel,0))
       ELSE round(100.0*z.ziel/NULLIF(i.ist,0)) END                        AS zielerreichung_pct,
  CASE WHEN z.richtung='hoch'    AND i.ist >= z.ziel        THEN '✅ erreicht'
       WHEN z.richtung='niedrig' AND i.ist <= z.ziel        THEN '✅ erreicht'
       WHEN z.richtung='hoch'    AND i.ist >= 0.9*z.ziel    THEN '🟡 nah dran'
       WHEN z.richtung='niedrig' AND i.ist <= 1.1*z.ziel    THEN '🟡 nah dran'
       ELSE '🔴 unter Ziel' END                                            AS status,
  z.ord
FROM core.dim_ziele z
JOIN ist i USING (kennzahl)
ORDER BY z.ord;
