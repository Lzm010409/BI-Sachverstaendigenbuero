-- 030_anwalt_klartext.sql — Anwalts-Namen im Klartext (Korrektur zu sql/029)
--
-- sql/029 hatte dim_anwalt vorsichtshalber per Kanzlei-Namensmuster gefiltert. Der
-- Inhaber stellt klar: die Anwalt-Orgs sind DURCHWEG Rechtsanwälte — Kanzleien ODER
-- Einzelanwälte unter Klarnamen, berufliche, öffentlich auffindbare Akteure, KEINE
-- Geschädigten. Das Namensmuster versteckte fälschlich echte Rechtsanwälte
-- (Einzelanwälte, „Legal-Navi GmbH", „RA Kalle", „Wittenberg&Collegen" …).
--
-- Korrektur: dim_anwalt = die vom Anwalt-Feld TATSÄCHLICH referenzierten Orgs, Name
-- im Klartext, kein Muster-Filter. Marts entsprechend, Fallback '(unbekannt)' nur
-- für deleted/archivierte Orgs, die nicht mehr in dim_organisation stehen.

CREATE OR REPLACE VIEW core.dim_anwalt AS
SELECT DISTINCT
  o.org_id AS anwalt_org_id,
  o.name   AS anwalt
FROM core.dim_organisation o
WHERE o.org_id IN (
  SELECT anwalt_org_id FROM core.fact_ausbuchung WHERE anwalt_org_id IS NOT NULL
);

-- LF4: bringt Umsatz UND zahlt zuverlässig? Je Anwalt Fälle/won/Umsatz/Ausfall.
CREATE OR REPLACE VIEW marts.v_anwalt AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  COALESCE(da.anwalt, '(unbekannt)')                   AS anwalt,
  count(*)                                             AS anzahl_faelle,
  count(*) FILTER (WHERE fa.won_time IS NOT NULL)      AS anzahl_won,
  sum(fa.deal_value_brutto)                            AS summe_fakturiert_brutto,
  round(avg(fa.deal_value_brutto), 2)                  AS schnitt_fakturiert_brutto,
  COALESCE(sum(fv.ausbuchung), 0)                      AS summe_forderungsverlust
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_anwalt        da ON da.anwalt_org_id = fa.anwalt_org_id
LEFT JOIN fv                        ON fv.aktenzeichen  = fa.aktenzeichen
WHERE fa.anwalt_org_id IS NOT NULL
GROUP BY 1;

-- Kreuzdimension Versicherer × Anwalt (Fälle & Umsatz).
CREATE OR REPLACE VIEW marts.v_versicherer_x_anwalt AS
SELECT
  COALESCE(NULLIF(trim(vo.name), ''), '(kein/unbekannter Versicherer)') AS versicherer,
  COALESCE(da.anwalt, '(unbekannt)')                                    AS anwalt,
  count(*)                                                              AS anzahl_faelle,
  sum(fa.deal_value_brutto)                                             AS summe_fakturiert_brutto
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_organisation vo ON vo.org_id = fa.org_id AND vo.typ = 'versicherer'
LEFT JOIN core.dim_anwalt       da ON da.anwalt_org_id = fa.anwalt_org_id
WHERE fa.anwalt_org_id IS NOT NULL OR fa.org_id IS NOT NULL
GROUP BY 1, 2;
