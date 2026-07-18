-- 037_honorar_km.sql — Honorar-Konformität (LF8) + Umsatz je km (LF7)
--
-- Referenz: eigene Honorartabelle des Büros (AGB, = BVSK-Korridor 50-60%), gepflegt in
-- fixtures/honorartabelle.json. dim_honorar_tabelle spiegelt die Grundhonorar-Stufen
-- (VALUES; bei Tarifänderung: JSON + diese VALUES pflegen, neue Migration). Schadenhöhe*
-- = Reparaturkosten netto + merkantile Wertminderung; bei Totalschaden/130%: WBW brutto.
-- Maßgeblich ist die nächsthöhere 'bis'-Stufe.

CREATE OR REPLACE VIEW core.dim_honorar_tabelle AS
SELECT * FROM (VALUES
  (500, 296.1, 352.36),
  (750, 330.75, 393.59),
  (1000, 388.5, 462.32),
  (1250, 430.5, 512.3),
  (1500, 467.25, 556.03),
  (1750, 499.8, 594.76),
  (2000, 528.15, 628.5),
  (2250, 554.4, 659.74),
  (2500, 581.7, 692.22),
  (2750, 607.95, 723.46),
  (3000, 631.05, 750.95),
  (3250, 655.2, 779.69),
  (3500, 679.35, 808.43),
  (3750, 703.5, 837.17),
  (4000, 727.65, 865.9),
  (4250, 748.65, 890.89),
  (4500, 771.75, 918.38),
  (4750, 790.65, 940.87),
  (5000, 810.6, 964.61),
  (5250, 829.5, 987.1),
  (5500, 850.5, 1012.09),
  (5750, 868.35, 1033.34),
  (6000, 890.4, 1059.58),
  (6500, 918.75, 1093.31),
  (7000, 949.2, 1129.55),
  (7500, 977.55, 1163.28),
  (8000, 1013.25, 1205.77),
  (8500, 1046.85, 1245.75),
  (9000, 1078.35, 1283.24),
  (9500, 1109.85, 1320.72),
  (10000, 1141.35, 1358.21),
  (10500, 1179.15, 1403.19),
  (11000, 1205.4, 1434.43),
  (11500, 1247.4, 1484.41),
  (12000, 1277.85, 1520.64),
  (12500, 1310.4, 1559.38),
  (13000, 1346.1, 1601.86),
  (13500, 1379.7, 1641.84),
  (14000, 1410.15, 1678.08),
  (14500, 1445.85, 1720.56),
  (15000, 1482.6, 1764.29),
  (16000, 1543.5, 1836.76),
  (17000, 1604.4, 1909.24),
  (18000, 1661.1, 1976.71),
  (19000, 1726.2, 2054.18),
  (20000, 1796.55, 2137.89),
  (21000, 1863.75, 2217.86),
  (22000, 1919.4, 2284.09),
  (23000, 1979.25, 2355.31),
  (24000, 2044.35, 2432.78),
  (25000, 2072.7, 2466.51),
  (26000, 2130.45, 2535.24),
  (27000, 2189.25, 2605.21),
  (28000, 2260.65, 2690.17),
  (29000, 2317.35, 2757.65),
  (30000, 2391.9, 2846.36),
  (32500, 2542.05, 3025.04),
  (35000, 2699.55, 3212.46),
  (37500, 2865.45, 3409.89),
  (40000, 3022.95, 3597.31),
  (42500, 3222.45, 3834.72),
  (45000, 3429.3, 4080.87),
  (47500, 3604.65, 4289.53),
  (50000, 3774.75, 4491.95)
) AS t(schaden_bis, honorar_netto, honorar_brutto);

-- --- LF8: Honorar-Konformität (fakturiert vs. Tabelle) ------------------------
CREATE OR REPLACE VIEW marts.v_honorar_konformitaet AS
WITH basis AS (
  SELECT aktenzeichen, ist_totalschaden,
    CASE WHEN ist_totalschaden THEN wiederbeschaffungswert
         ELSE reparaturkosten_netto + COALESCE(wertminderung,0) END AS schaden_basis
  FROM core.fact_gutachten
),
soll AS (
  SELECT b.aktenzeichen, b.ist_totalschaden, b.schaden_basis,
    (SELECT min(honorar_netto) FROM core.dim_honorar_tabelle t WHERE t.schaden_bis >= b.schaden_basis) AS honorar_soll_netto
  FROM basis b WHERE b.schaden_basis IS NOT NULL
),
ist AS (
  SELECT aktenzeichen, sum(summe_netto) AS honorar_ist_netto
  FROM core.fact_rechnungsposition WHERE kategorie='Grundhonorar' GROUP BY aktenzeichen
)
SELECT
  s.aktenzeichen, s.ist_totalschaden,
  round(s.schaden_basis,2)                          AS schaden_basis,
  s.honorar_soll_netto,
  i.honorar_ist_netto,
  round(i.honorar_ist_netto - s.honorar_soll_netto, 2) AS abweichung_netto,
  CASE WHEN abs(i.honorar_ist_netto - s.honorar_soll_netto) <= 1 THEN 'konform'
       WHEN i.honorar_ist_netto < s.honorar_soll_netto            THEN 'unter Tabelle'
       ELSE 'über Tabelle' END                       AS befund
FROM soll s JOIN ist i USING (aktenzeichen)
WHERE s.honorar_soll_netto IS NOT NULL AND i.honorar_ist_netto > 0;

-- --- LF7: Umsatz je gefahrenem km --------------------------------------------
-- km aus der Fahrtkosten-Position (einheit='km'); Pauschale ('zu weit') hat keine
-- km und bleibt außen vor. Umsatz = fakturierte Rechnungssumme (fact_ausbuchung).
CREATE OR REPLACE VIEW marts.v_umsatz_je_km AS
WITH km AS (
  SELECT aktenzeichen, sum(menge) AS km
  FROM core.fact_rechnungsposition
  WHERE kategorie='Fahrtkosten' AND einheit ILIKE 'km' AND menge > 1
  GROUP BY aktenzeichen
)
SELECT
  COALESCE(geo.plz_gebiet, '(unbekannt)')            AS plz_gebiet,
  count(*)                                           AS anzahl_faelle,
  round(sum(k.km))                                   AS summe_km,
  round(sum(fa.deal_value_brutto))                   AS summe_umsatz_brutto,
  round(sum(fa.deal_value_brutto) / NULLIF(sum(k.km),0), 2) AS umsatz_je_km
FROM km k
JOIN core.fact_ausbuchung fa ON fa.aktenzeichen = k.aktenzeichen
LEFT JOIN core.dim_fall_geo geo ON geo.aktenzeichen = k.aktenzeichen
GROUP BY 1;
