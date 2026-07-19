-- 043_geo_plz4_views.sql — 4-stellige PLZ in die Geo-Views + Karten-Aggregat
--
-- Erweitert dim_fall_geo/v_fall_geo um plz4 (neue Spalte am ENDE → CREATE OR REPLACE
-- bleibt gültig) und liefert v_geo_je_plz4 mit Lat/Lon (aus core.dim_plz_geo) für
-- die Metabase-Karte und die Heatmap. DSGVO: Anzeige nur ab 3 Fällen je plz4.

-- Fall -> Geo inkl. plz4
CREATE OR REPLACE VIEW core.dim_fall_geo AS
SELECT
  aktenzeichen,
  max(plz_gebiet) AS plz_gebiet,
  max(ort)        AS ort,
  max(plz4)       AS plz4
FROM (
  SELECT
    upper(regexp_replace(d.payload->>'title', '\s', '', 'g')) AS aktenzeichen,
    g.plz_gebiet,
    g.ort,
    g.plz4
  FROM raw.pipedrive_deals d
  JOIN raw.pipedrive_person_geo g
    ON g.person_id = NULLIF(d.payload->>'person_id', '')::bigint
  WHERE upper(regexp_replace(d.payload->>'title', '\s', '', 'g')) ~ '^\d{4}/\d+TG$'
) s
GROUP BY aktenzeichen;

-- Basis-View um plz4 ergänzt (neue Spalte am Ende)
CREATE OR REPLACE VIEW marts.v_fall_geo AS
SELECT
  fa.aktenzeichen,
  geo.plz_gebiet,
  geo.ort,
  fa.deal_value_brutto        AS fakturiert_brutto,
  fa.won_time,
  g.schadenhoehe_brutto,
  g.ist_totalschaden,
  geo.plz4
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_fall_geo   geo USING (aktenzeichen)
LEFT JOIN core.fact_gutachten g   USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL;

-- LF7: Kennzahlen je 4-stelliger PLZ inkl. Centroid (für Karte/Heatmap)
CREATE OR REPLACE VIEW marts.v_geo_je_plz4 AS
SELECT
  g.plz4,
  pg.lat,
  pg.lon,
  count(*)                                              AS anzahl_faelle,
  sum(g.fakturiert_brutto)                              AS summe_fakturiert_brutto,
  round(avg(g.fakturiert_brutto), 2)                    AS schnitt_fakturiert_brutto,
  round(avg(g.schadenhoehe_brutto), 2)                  AS schnitt_schadenhoehe_brutto,
  count(*) FILTER (WHERE g.ist_totalschaden)            AS anzahl_totalschaden,
  round(100.0 * count(*) FILTER (WHERE g.ist_totalschaden) / count(*), 1) AS totalschaden_quote_pct
FROM marts.v_fall_geo g
LEFT JOIN core.dim_plz_geo pg ON pg.plz4 = g.plz4
WHERE g.plz4 IS NOT NULL
GROUP BY g.plz4, pg.lat, pg.lon
HAVING count(*) >= 3;   -- DSGVO: keine Einzel-/Kleinstfälle je Feinraster
