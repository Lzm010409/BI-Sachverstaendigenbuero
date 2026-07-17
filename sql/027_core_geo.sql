-- 027_core_geo.sql — Einzugsgebiet-Dimension + Geo-Marts (Leitfrage 7)
--
-- Verknüpft jeden Fall (Aktenzeichen) mit dem PLZ-Gebiet und Ort des Geschädigten
-- (raw.pipedrive_person_geo über deal.person_id). Alle Beträge brutto.
-- DSGVO: nur PLZ-Gebiet (2-stellig) + Ort; kein Name/keine Straße (bereits in raw
-- ausgefiltert).

-- --- Fall -> Geo (Grain: ein Aktenzeichen) ----------------------------------
CREATE OR REPLACE VIEW core.dim_fall_geo AS
SELECT
  aktenzeichen,
  max(plz_gebiet) AS plz_gebiet,
  max(ort)        AS ort
FROM (
  SELECT
    upper(regexp_replace(d.payload->>'title', '\s', '', 'g')) AS aktenzeichen,
    g.plz_gebiet,
    g.ort
  FROM raw.pipedrive_deals d
  JOIN raw.pipedrive_person_geo g
    ON g.person_id = NULLIF(d.payload->>'person_id', '')::bigint
  WHERE upper(regexp_replace(d.payload->>'title', '\s', '', 'g')) ~ '^\d{4}/\d+TG$'
) s
GROUP BY aktenzeichen;

-- --- Basis-View: ein won-Fall mit Geo + Umsatz + Schaden --------------------
CREATE OR REPLACE VIEW marts.v_fall_geo AS
SELECT
  fa.aktenzeichen,
  geo.plz_gebiet,
  geo.ort,
  fa.deal_value_brutto        AS fakturiert_brutto,
  fa.won_time,
  g.schadenhoehe_brutto,
  g.ist_totalschaden
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_fall_geo   geo USING (aktenzeichen)
LEFT JOIN core.fact_gutachten g   USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL;

-- --- LF7: Kennzahlen je PLZ-Gebiet ------------------------------------------
CREATE OR REPLACE VIEW marts.v_geo_je_plzgebiet AS
SELECT
  COALESCE(plz_gebiet, '(unbekannt)')                 AS plz_gebiet,
  count(*)                                            AS anzahl_faelle,
  sum(fakturiert_brutto)                              AS summe_fakturiert_brutto,
  round(avg(fakturiert_brutto), 2)                    AS schnitt_fakturiert_brutto,
  round(avg(schadenhoehe_brutto), 2)                  AS schnitt_schadenhoehe_brutto,
  count(*) FILTER (WHERE ist_totalschaden)            AS anzahl_totalschaden
FROM marts.v_fall_geo
GROUP BY 1;

-- --- LF7: Kennzahlen je Stadt/Ort -------------------------------------------
CREATE OR REPLACE VIEW marts.v_geo_je_ort AS
SELECT
  COALESCE(ort, '(unbekannt)')                        AS ort,
  max(plz_gebiet)                                     AS plz_gebiet,
  count(*)                                            AS anzahl_faelle,
  sum(fakturiert_brutto)                              AS summe_fakturiert_brutto,
  round(avg(schadenhoehe_brutto), 2)                  AS schnitt_schadenhoehe_brutto,
  count(*) FILTER (WHERE ist_totalschaden)            AS anzahl_totalschaden
FROM marts.v_fall_geo
GROUP BY 1;
