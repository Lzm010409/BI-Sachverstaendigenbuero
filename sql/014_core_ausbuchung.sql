-- 014_core_ausbuchung.sql — Phase 5 KORREKTUR nach Prod-Verifikation (2026-07-16)
--
-- BEFUND an Echtdaten: `sumGross − paidAmount` (fact_kuerzung) misst NICHT die
-- Kürzung. In sevDesk wird die Rechnung bei Fallabschluss voll gebucht (Zahlung +
-- Ausbuchungsbuchung) → offener Betrag ist ~0 (Cent), selbst wenn real z. B. 1712 €
-- abgeschrieben wurden. Von 515 „Kürzungen" waren 506 < 0,10 € (Rundung), der Rest
-- unbezahlte Einzelfälle. Die ECHTE Kürzung (Versicherer-Behauptung) steht nur im
-- Kürzungsschreiben (eigene Quelle, s. docs/strategie-kuerzung-und-pdf.md).
--
-- Zuverlässig ist die AUSBUCHUNG aus den Forderungsverlust-Belegen
-- (core.fact_forderungsverlust, 89 Fälle / 34 k€ live). Diese Migration macht sie
-- zur Hauptlieferung (Leitfrage 5: wo entstehen Zahlungsausfälle) und entschärft die
-- irreführenden Kürzungs-Views mit einer Bagatellgrenze.

-- --- Ausbuchung je Versicherer (Leitfrage 5) --------------------------------
-- Versicherer über den Fall (fact_ausbuchung.org_id → dim_organisation). Namen sind
-- dirty (Phase 4/autoiXpert liefert später die saubere Versicherer-Zuordnung).
CREATE OR REPLACE VIEW marts.v_forderungsverlust_je_versicherer AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung, count(*) AS belege
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  COALESCE(NULLIF(trim(dorg.name), ''), '(unbekannt)') AS versicherer,
  count(*)                                              AS anzahl_faelle,
  sum(fv.ausbuchung)                                    AS summe_ausbuchung,
  round(avg(fv.ausbuchung), 2)                          AS schnitt_ausbuchung
FROM fv
LEFT JOIN core.fact_ausbuchung fa ON fa.aktenzeichen = fv.aktenzeichen
LEFT JOIN core.dim_organisation  dorg ON dorg.org_id = fa.org_id AND dorg.typ = 'versicherer'
GROUP BY 1;

-- --- Ausbuchung je Monat (Zahlungsausfall-Zeitreihe) ------------------------
CREATE OR REPLACE VIEW marts.v_forderungsverlust_monat AS
SELECT
  date_trunc('month', beleg_datum)::date AS monat,
  count(*)                                AS anzahl_belege,
  sum(forderungsverlust_brutto)           AS summe_ausbuchung
FROM core.fact_forderungsverlust
WHERE beleg_datum IS NOT NULL
GROUP BY 1;

-- --- Kürzungs-Views mit Bagatellgrenze neu fassen (Cent-Rauschen raus) -------
-- >= 1 € gilt als echte Kürzung. HINWEIS: diese Views bleiben nur belastbar, sobald
-- die Kürzung aus dem Kürzungsschreiben kommt; aus der Rechnungsdifferenz sind sie
-- weitgehend leer/irreführend (s. Befund oben).
-- DROP nötig: CREATE OR REPLACE darf keine Spalte entfernen (kuerzungsquote raus).
DROP VIEW IF EXISTS marts.v_kuerzung_je_versicherer;
CREATE VIEW marts.v_kuerzung_je_versicherer AS
SELECT
  COALESCE(NULLIF(trim(versicherer), ''), '(unbekannt)') AS versicherer,
  count(*)                                          AS anzahl_rechnungen,
  count(*) FILTER (WHERE kuerzung_betrag >= 1)       AS anzahl_gekuerzt,
  sum(rechnung_brutto)                              AS summe_rechnung_brutto,
  sum(kuerzung_betrag) FILTER (WHERE kuerzung_betrag >= 1) AS summe_kuerzung
FROM core.fact_kuerzung
WHERE kuerzung_betrag IS NOT NULL
  AND NOT ist_haftungsquote
  AND NOT ist_mwst_einbehalt
GROUP BY 1;

-- v_durchsetzung: Bagatellgrenze anwenden. Ergebnis ist bewusst spärlich — es
-- dokumentiert, dass die Durchsetzungsquote aus Rechnungsdifferenz vs. Beleg NICHT
-- messbar ist (offener Betrag ~0 trotz realer Ausbuchung). Echte Durchsetzungsquote
-- erst mit Kürzungsschreiben-Quelle.
DROP VIEW IF EXISTS marts.v_durchsetzung;
CREATE VIEW marts.v_durchsetzung AS
WITH kuerzung AS (
  SELECT aktenzeichen, max(versicherer) AS versicherer, sum(kuerzung_betrag) AS kuerzung
  FROM core.fact_kuerzung
  WHERE kuerzung_betrag >= 1 AND NOT ist_haftungsquote AND NOT ist_mwst_einbehalt
  GROUP BY aktenzeichen
),
ausbuchung AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust WHERE aktenzeichen IS NOT NULL GROUP BY aktenzeichen
)
SELECT
  COALESCE(NULLIF(trim(k.versicherer), ''), '(unbekannt)') AS versicherer,
  count(*)                                          AS anzahl_faelle,
  sum(k.kuerzung)                                   AS summe_kuerzung,
  sum(COALESCE(a.ausbuchung, 0))                    AS summe_ausbuchung,
  sum(k.kuerzung) - sum(COALESCE(a.ausbuchung, 0))  AS summe_durchgesetzt,
  1 - sum(COALESCE(a.ausbuchung, 0)) / NULLIF(sum(k.kuerzung), 0) AS durchsetzungsquote
FROM kuerzung k
LEFT JOIN ausbuchung a ON a.aktenzeichen = k.aktenzeichen
GROUP BY 1;
