-- 038_deckungsbeitrag.sql — Deckungsbeitrag je Fall (LF1)
--
-- Kostenmodell (Inhaber, fixtures/kostenmodell.json — Konstanten hier gespiegelt):
--   Stundenkostensatz netto = 53 €/h  (Personal 5818 €/Mon / ~110 produktive h)
--   Stunden je Gutachten    = 2,5 h
--   km-Kosten netto         = 0,72 €/km  (real; berechnet werden 0,80)
--   Externe je Anlass netto = Restwertbörse 19 · Bewertungsabfrage 11 (Vermessung 120
--                             mangels Positions-Signal noch nicht zugeordnet)
--   Sachfixkosten           = 5500 €/Mon (ohne Personal) → Umlage 5500/30 = 183,33 €/Fall
--
-- Zwei Sichten:
--   db_i         = Erlös − echte variable Kosten (km + externe)   [Deckungsbeitrag I]
--   db_vollkosten= Erlös − Zeit − km − externe − Fixkosten-Umlage [Vollkosten-Marge]
-- Erlös NETTO (deal_value − enthaltene_mwst, sonst /1,19). Nur won-Fälle.
-- HINWEIS: aktueller (teils nebenberuflicher) Kostenstand; hauptberuflicher GF-Lohn
-- höbe den Stundensatz. Werte in der Fixture pflegen → neue Migration.

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
  round(2.5 * 53, 2)                                                         AS zeit_kosten,
  round(COALESCE(km.km, 0) * 0.72, 2)                                        AS km_kosten,
  COALESCE(ext.externe, 0)::numeric                                          AS externe_kosten,
  round(5500.0 / 30, 2)                                                      AS fix_umlage,
  -- Deckungsbeitrag I (nur echte variable Kosten)
  round((CASE WHEN fa.enthaltene_mwst IS NOT NULL THEN fa.deal_value_brutto - fa.enthaltene_mwst
              ELSE fa.deal_value_brutto / 1.19 END)
        - COALESCE(km.km,0)*0.72 - COALESCE(ext.externe,0), 2)               AS db_i,
  -- Vollkosten-Marge
  round((CASE WHEN fa.enthaltene_mwst IS NOT NULL THEN fa.deal_value_brutto - fa.enthaltene_mwst
              ELSE fa.deal_value_brutto / 1.19 END)
        - 2.5*53 - COALESCE(km.km,0)*0.72 - COALESCE(ext.externe,0) - 5500.0/30, 2) AS db_vollkosten
FROM core.fact_ausbuchung fa
LEFT JOIN km  USING (aktenzeichen)
LEFT JOIN ext USING (aktenzeichen)
LEFT JOIN art USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL AND fa.deal_value_brutto > 0;

-- --- LF1: DB je Auftragsart ---------------------------------------------------
CREATE OR REPLACE VIEW marts.v_deckungsbeitrag_je_auftragsart AS
SELECT auftragsart,
  count(*)                          AS anzahl_faelle,
  round(sum(erloes_netto))          AS summe_erloes_netto,
  round(avg(erloes_netto))          AS schnitt_erloes,
  round(avg(db_i))                  AS schnitt_db_i,
  round(avg(db_vollkosten))         AS schnitt_db_vollkosten,
  round(sum(db_vollkosten))         AS summe_db_vollkosten,
  round(100.0*avg(db_vollkosten)/NULLIF(avg(erloes_netto),0),1) AS marge_pct
FROM core.fact_deckungsbeitrag GROUP BY 1;

-- --- DB je Versicherer (kanonisiert) -----------------------------------------
CREATE OR REPLACE VIEW marts.v_deckungsbeitrag_je_versicherer AS
SELECT COALESCE(vk.versicherer,'(unbekannt)') AS versicherer,
  count(*)                   AS anzahl_faelle,
  round(sum(d.erloes_netto)) AS summe_erloes_netto,
  round(avg(d.db_vollkosten))AS schnitt_db_vollkosten,
  round(sum(d.db_vollkosten))AS summe_db_vollkosten,
  round(100.0*avg(d.db_vollkosten)/NULLIF(avg(d.erloes_netto),0),1) AS marge_pct
FROM core.fact_deckungsbeitrag d
JOIN core.fact_ausbuchung fa USING (aktenzeichen)
LEFT JOIN core.dim_versicherer_kanon vk ON vk.org_id = fa.org_id
GROUP BY 1;

-- --- DB je Anwalt/Kanzlei ----------------------------------------------------
CREATE OR REPLACE VIEW marts.v_deckungsbeitrag_je_anwalt AS
SELECT COALESCE(aw.name,'(kein Anwalt erfasst)') AS anwalt,
  count(*)                    AS anzahl_faelle,
  round(sum(d.erloes_netto))  AS summe_erloes_netto,
  round(avg(d.db_vollkosten)) AS schnitt_db_vollkosten,
  round(sum(d.db_vollkosten)) AS summe_db_vollkosten
FROM core.fact_deckungsbeitrag d
JOIN core.fact_ausbuchung fa USING (aktenzeichen)
LEFT JOIN core.dim_organisation aw ON aw.org_id = fa.anwalt_org_id
GROUP BY 1;

-- --- DB je Monat -------------------------------------------------------------
CREATE OR REPLACE VIEW marts.v_deckungsbeitrag_monat AS
SELECT date_trunc('month', fa.won_time)::date AS monat,
  count(*)                    AS anzahl_faelle,
  round(sum(d.erloes_netto))  AS summe_erloes_netto,
  round(sum(d.db_vollkosten)) AS summe_db_vollkosten
FROM core.fact_deckungsbeitrag d
JOIN core.fact_ausbuchung fa USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL
GROUP BY 1;
