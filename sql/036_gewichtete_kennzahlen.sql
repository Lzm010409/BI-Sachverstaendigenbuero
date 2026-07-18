-- 036_gewichtete_kennzahlen.sql — gewichtete Entscheidungs-Kennzahlen
--
-- Zwei Gewichtungen, damit aus Rohzahlen belastbare Ranglisten werden:
--
-- (1) KONFIDENZ-GEWICHTUNG (Shrinkage / empirical Bayes) auf die Durchsetzungsquote.
--     Problem: ein Versicherer mit n=1 und 0 % darf nicht schlechter ranken als einer
--     mit n=66 und 82 %. Lösung: eigenen Wert mit dem Gesamtmittel mischen, gewichtet
--     nach Fallzahl:  quote_gew = (n·quote + k·µ) / (n + k),  k = Prior-Stärke (5 Fälle).
--     n klein → Richtung µ gezogen; n groß → fast eigener Wert. `k` ist der Stellhebel.
--
-- (2) AUFTRAGGEBER-WERTIGKEIT (LF4): realisierter Umsatz = Umsatz × Zahlungs­zuver­
--     lässigkeit × (konfidenz-gewichtete) Durchsetzung. Eine Zahl für „wer lohnt sich".
--
-- Alle Beträge brutto. Baut nur auf vorhandenen marts-Views auf.

-- --- (1a) Durchsetzung je Versicherer, konfidenz-gewichtet ---------------------
CREATE OR REPLACE VIEW marts.v_durchsetzung_versicherer_gewichtet AS
WITH g AS (
  SELECT round(1 - sum(ausgebucht) / NULLIF(sum(kuerzung), 0), 4) AS mu
  FROM marts.v_durchsetzung_zahlung
)
SELECT
  p.versicherer,
  p.anzahl_faelle,
  p.summe_kuerzung,
  p.summe_ausbuchung,
  p.durchsetzungsquote                                                       AS quote_roh,
  round((p.anzahl_faelle * p.durchsetzungsquote + 5 * g.mu) / (p.anzahl_faelle + 5), 4) AS durchsetzungsquote_gew,
  g.mu                                                                       AS quote_global
FROM marts.v_durchsetzung_zahlung_je_versicherer p
CROSS JOIN g;

-- --- (1b) Durchsetzung je Anwalt, konfidenz-gewichtet -------------------------
CREATE OR REPLACE VIEW marts.v_durchsetzung_anwalt_gewichtet AS
WITH g AS (
  SELECT round(1 - sum(ausgebucht) / NULLIF(sum(kuerzung), 0), 4) AS mu
  FROM marts.v_durchsetzung_zahlung
)
SELECT
  p.anwalt,
  p.anzahl_faelle,
  p.summe_kuerzung,
  p.summe_ausbuchung,
  p.durchsetzungsquote                                                       AS quote_roh,
  round((p.anzahl_faelle * p.durchsetzungsquote + 5 * g.mu) / (p.anzahl_faelle + 5), 4) AS durchsetzungsquote_gew,
  g.mu                                                                       AS quote_global
FROM marts.v_durchsetzung_zahlung_je_anwalt p
CROSS JOIN g;

-- --- (2) Auftraggeber-Wertigkeit (LF4) ---------------------------------------
-- realisierter_umsatz = Umsatz − Forderungsverlust (Umsatz gewichtet mit Zahlungs­
-- zuverlässigkeit). wertigkeit_score multipliziert zusätzlich mit der konfidenz-
-- gewichteten Durchsetzung; fehlt Kürzungshistorie zum Anwalt, wird das Gesamtmittel
-- als Prior verwendet (Unbekanntes = Durchschnitt, konsistent mit der Shrinkage-Idee).
CREATE OR REPLACE VIEW marts.v_anwalt_wertigkeit AS
WITH g AS (
  SELECT round(1 - sum(ausgebucht) / NULLIF(sum(kuerzung), 0), 4) AS mu
  FROM marts.v_durchsetzung_zahlung
)
SELECT
  a.anwalt,
  a.anzahl_faelle,
  a.summe_fakturiert_brutto                                                   AS umsatz,
  a.summe_forderungsverlust                                                   AS forderungsverlust,
  round(1 - a.summe_forderungsverlust / NULLIF(a.summe_fakturiert_brutto, 0), 4) AS zahlungszuverlaessigkeit,
  round(a.summe_fakturiert_brutto - a.summe_forderungsverlust, 2)             AS realisierter_umsatz,
  COALESCE(dg.durchsetzungsquote_gew, g.mu)                                   AS durchsetzung_gew,
  round((a.summe_fakturiert_brutto - a.summe_forderungsverlust)
        * COALESCE(dg.durchsetzungsquote_gew, g.mu), 2)                       AS wertigkeit_score
FROM marts.v_anwalt a
CROSS JOIN g
LEFT JOIN marts.v_durchsetzung_anwalt_gewichtet dg ON dg.anwalt = a.anwalt
WHERE a.anwalt <> '(unbekannt)';
