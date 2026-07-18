-- 041_deckungsbeitrag_fixumlage_zeitgewichtet.sql
--
-- Korrektur zu sql/038: Fixkosten-Umlage ZEITGEWICHTET statt pauschal.
-- sql/038 ist bereits angewandt (Umlage pauschal 5500/30 = 183,33 €/Fall) und darf
-- deshalb nicht editiert werden (Drift-Schutz im Migrations-Runner). Diese neue
-- Migration ersetzt die View per CREATE OR REPLACE.
--
-- NEU: fix_satz = fixkosten/produktive_stunden = 5500/110 h = 50 €/h.
--      Umlage je Fall = Stunden · 50  →  Haftpflicht 2,5 h = 125 € · Bewertung 1,25 h = 62,50 €.
-- Gleiche 110-h-Basis wie der Stundenkostensatz (53 €/h). Ein kurzes Bewertungs-
-- gutachten trägt so nur die gebundene Kapazität statt pauschal 1/30 des Monats;
-- Bewertung dreht dadurch von −15,6 % auf +38,5 % Marge, Haftpflicht auf ~69 %.
-- Spalten-Signatur identisch zu 038 → abhängige marts.v_deckungsbeitrag_*-Views
-- bleiben ohne DROP gültig.

CREATE OR REPLACE VIEW core.fact_deckungsbeitrag AS
WITH km AS (
  SELECT aktenzeichen, sum(menge) AS km
  FROM core.fact_rechnungsposition
  WHERE kategorie='Fahrtkosten' AND einheit ILIKE 'km' AND menge > 1
  GROUP BY aktenzeichen
),
ext AS (
  SELECT aktenzeichen,
    (CASE WHEN bool_or(kategorie='Restwertermittlung') THEN 19 ELSE 0 END)
  + (CASE WHEN bool_or(kategorie='Bewertungsabfrage')  THEN 11 ELSE 0 END) AS externe
  FROM core.fact_rechnungsposition GROUP BY aktenzeichen
),
art AS (
  SELECT aktenzeichen,
    CASE WHEN beurteilung ILIKE 'Bewertung%' THEN 'Bewertung' ELSE 'Haftpflicht' END AS auftragsart
  FROM core.fact_gutachten
)
SELECT
  fa.aktenzeichen,
  COALESCE(art.auftragsart, 'Haftpflicht')                                   AS auftragsart,
  CASE WHEN fa.enthaltene_mwst IS NOT NULL THEN fa.deal_value_brutto - fa.enthaltene_mwst
       ELSE round(fa.deal_value_brutto / 1.19, 2) END                        AS erloes_netto,
  round((CASE WHEN COALESCE(art.auftragsart,'Haftpflicht')='Bewertung' THEN 1.25 ELSE 2.5 END) * 53, 2) AS zeit_kosten,
  round(COALESCE(km.km, 0) * 0.72, 2)                                        AS km_kosten,
  COALESCE(ext.externe, 0)::numeric                                          AS externe_kosten,
  round((CASE WHEN COALESCE(art.auftragsart,'Haftpflicht')='Bewertung' THEN 1.25 ELSE 2.5 END) * (5500.0/110), 2) AS fix_umlage,
  -- Deckungsbeitrag I (nur echte variable Kosten)
  round((CASE WHEN fa.enthaltene_mwst IS NOT NULL THEN fa.deal_value_brutto - fa.enthaltene_mwst
              ELSE fa.deal_value_brutto / 1.19 END)
        - COALESCE(km.km,0)*0.72 - COALESCE(ext.externe,0), 2)               AS db_i,
  -- Vollkosten-Marge (Fixkosten zeitgewichtet: Stunden · 5500/110)
  round((CASE WHEN fa.enthaltene_mwst IS NOT NULL THEN fa.deal_value_brutto - fa.enthaltene_mwst
              ELSE fa.deal_value_brutto / 1.19 END)
        - (CASE WHEN COALESCE(art.auftragsart,'Haftpflicht')='Bewertung' THEN 1.25 ELSE 2.5 END)*53
        - COALESCE(km.km,0)*0.72 - COALESCE(ext.externe,0)
        - (CASE WHEN COALESCE(art.auftragsart,'Haftpflicht')='Bewertung' THEN 1.25 ELSE 2.5 END)*(5500.0/110), 2) AS db_vollkosten
FROM core.fact_ausbuchung fa
LEFT JOIN km  USING (aktenzeichen)
LEFT JOIN ext USING (aktenzeichen)
LEFT JOIN art USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL AND fa.deal_value_brutto > 0;
