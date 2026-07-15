-- 010_core_kuerzung.sql — Phase 5: Kürzung je Rechnung (Durchsetzungs-Fundament)
--
-- Reproduzierbar aus raw/core, kein Transform-Schritt, kein dbt. Views.
--
-- Domänenregeln (CLAUDE.md, nicht verhandelbar, über jeder Faustregel):
--   - Kürzung ≠ Ausbuchung ≠ Haftungsquote. Alle Beträge BRUTTO. null ≠ 0.
--   - Haftungsquote/Teilschuld ist KEINE Kürzung → getrennt halten.
--
-- Kürzungsdefinition (mit Inhaber 2026-07-15 festgelegt, Quelle „sevDesk-Differenz"):
--   offener_betrag := sumGross - paidAmount   (je sevDesk-Rechnung)
--   Der offene Betrag IST die Kürzung — AUSSER er entspricht (±5 ct) der MwSt der
--   Rechnung: dann hat der Versicherer die USt einbehalten (Geschädigter
--   vorsteuerabzugsberechtigt) → KEINE Kürzung.
--   Nur GESCHLOSSENE Fälle (Pipedrive status='won'); bei offenen ist die Differenz
--   nur „noch nicht bezahlt". paidAmount null → keine Aussage (kuerzung = null).
--   Teilschuld/Haftungsquote (ausgebucht_grund 71) → markiert, aus dem Kürzungstopf
--   ausgeschlossen.
--
-- Join zum Fall über das Aktenzeichen (kanonischer Key, CLAUDE.md): das
-- Aktenzeichen-Präfix der sevDesk-invoiceNumber == deal-Aktenzeichen.

-- --- fact_kuerzung (Grain: eine sevDesk-Rechnung eines geschlossenen Falls) -----
CREATE OR REPLACE VIEW core.fact_kuerzung AS
WITH inv AS (
  SELECT
    id                                                        AS invoice_id,
    payload->>'invoiceNumber'                                 AS rechnungsnummer,
    substring(payload->>'invoiceNumber' FROM '^\d{4}/\d+TG')  AS aktenzeichen,
    (payload->>'invoiceDate')::timestamptz                    AS rechnungsdatum,
    (payload->>'sumGross')::numeric(12,2)                     AS rechnung_brutto,
    (payload->>'sumTax')::numeric(12,2)                       AS rechnung_steuer,
    -- paidAmount: null ≠ 0. null = nie erfasst → keine Kürzungsaussage möglich.
    NULLIF(payload->>'paidAmount', '')::numeric(12,2)         AS bezahlt
  FROM raw.sevdesk_invoices
)
SELECT
  COALESCE(fa.aktenzeichen, inv.aktenzeichen)                 AS aktenzeichen,
  inv.invoice_id,
  inv.rechnungsnummer,
  inv.rechnungsdatum,
  inv.rechnung_brutto,
  inv.rechnung_steuer,
  inv.bezahlt,
  (inv.rechnung_brutto - inv.bezahlt)                        AS offener_betrag,
  -- USt-Einbehalt: offener Betrag ≈ MwSt (±5 ct) → keine Kürzung.
  (abs((inv.rechnung_brutto - inv.bezahlt) - inv.rechnung_steuer) <= 0.05) AS ist_mwst_einbehalt,
  -- Haftungsquote/Teilschuld (grund 71) → keine Kürzung.
  COALESCE(fa.ausgebucht_grund_id = 71, false)               AS ist_haftungsquote,
  ag.grund                                                    AS ausbuchungsgrund,
  fa.ausgebucht_betrag,
  fa.status,
  fa.won_time,
  fa.org_id,
  dorg.name                                                   AS versicherer,
  -- Echter Kürzungsbetrag: USt-Einbehalt & Haftungsquote = 0; unbekannt = null.
  CASE
    WHEN inv.bezahlt IS NULL                                                     THEN NULL
    WHEN abs((inv.rechnung_brutto - inv.bezahlt) - inv.rechnung_steuer) <= 0.05  THEN 0
    WHEN COALESCE(fa.ausgebucht_grund_id = 71, false)                           THEN 0
    WHEN (inv.rechnung_brutto - inv.bezahlt) <= 0                               THEN 0
    ELSE (inv.rechnung_brutto - inv.bezahlt)
  END                                                         AS kuerzung_betrag
FROM inv
JOIN core.fact_ausbuchung fa ON fa.aktenzeichen = inv.aktenzeichen
LEFT JOIN core.dim_organisation   dorg ON dorg.org_id  = fa.org_id AND dorg.typ = 'versicherer'
LEFT JOIN core.dim_ausbuchungsgrund ag ON ag.grund_id = fa.ausgebucht_grund_id
WHERE fa.status = 'won';   -- nur geschlossene Fälle

-- --- marts ------------------------------------------------------------------

-- LF2: welcher Versicherer kürzt wie oft, mit welchem Betrag? (echte Kürzungen)
CREATE OR REPLACE VIEW marts.v_kuerzung_je_versicherer AS
SELECT
  COALESCE(versicherer, '(unbekannt)')             AS versicherer,
  count(*)                                          AS anzahl_rechnungen,
  count(*) FILTER (WHERE kuerzung_betrag > 0)       AS anzahl_gekuerzt,
  sum(rechnung_brutto)                              AS summe_rechnung_brutto,
  sum(kuerzung_betrag)                              AS summe_kuerzung,
  sum(kuerzung_betrag) / NULLIF(sum(rechnung_brutto), 0) AS kuerzungsquote
FROM core.fact_kuerzung
WHERE kuerzung_betrag IS NOT NULL
  AND NOT ist_haftungsquote
  AND NOT ist_mwst_einbehalt
GROUP BY 1;

-- LF2/LF3: Kürzungen nach (Ausbuchungs-)Grund. Teilschuld/Haftungsquote SEPARAT
-- sichtbar (eigene Zeile), aber NICHT im Kürzungstopf der obigen View.
CREATE OR REPLACE VIEW marts.v_kuerzung_je_grund AS
SELECT
  CASE WHEN ist_haftungsquote THEN 'Haftungsquote (keine Kürzung)'
       ELSE COALESCE(ausbuchungsgrund, '(ohne Grund)') END AS grund,
  ist_haftungsquote,
  count(*)                                          AS anzahl,
  sum(kuerzung_betrag)                              AS summe_kuerzung
FROM core.fact_kuerzung
WHERE kuerzung_betrag IS NOT NULL AND NOT ist_mwst_einbehalt
GROUP BY 1, 2;

-- Zeitreihe der Kürzungen (echte Kürzungen, ohne Haftungsquote/USt-Einbehalt).
CREATE OR REPLACE VIEW marts.v_kuerzung_monat AS
SELECT
  date_trunc('month', rechnungsdatum)::date         AS monat,
  count(*) FILTER (WHERE kuerzung_betrag > 0)        AS anzahl_gekuerzt,
  sum(kuerzung_betrag)                               AS summe_kuerzung
FROM core.fact_kuerzung
WHERE rechnungsdatum IS NOT NULL AND kuerzung_betrag IS NOT NULL
  AND NOT ist_haftungsquote AND NOT ist_mwst_einbehalt
GROUP BY 1;

-- LF3-Fundament: Kürzung (sevDesk) vs. Ausbuchung (Pipedrive) gegenübergestellt.
-- Durchsetzung = Kürzung − Ausbuchung; Durchsetzungsquote = 1 − ΣAusbuchung/ΣKürzung.
-- HINWEIS: aussagekräftig nur, wenn die Ausbuchung UNABHÄNGIG vom finalen paidAmount
-- erfasst wird. Sind sevDesk-Differenz und ausgebucht_betrag praktisch gleich, ist
-- die Quote ~0 (dann fehlt ein separates Stellungnahme-Erfolg-Signal — s.
-- plan-phase-5 §8). Diese View macht genau das sichtbar (zum Verifizieren an Echt-
-- daten). Nur Fälle mit erfasster Ausbuchung (ist_erfasst) und echter Kürzung.
CREATE OR REPLACE VIEW marts.v_durchsetzung AS
SELECT
  COALESCE(versicherer, '(unbekannt)')             AS versicherer,
  count(*)                                          AS anzahl_faelle,
  sum(kuerzung_betrag)                              AS summe_kuerzung,
  sum(ausgebucht_betrag)                            AS summe_ausbuchung,
  sum(kuerzung_betrag) - sum(ausgebucht_betrag)     AS summe_durchgesetzt,
  1 - (sum(ausgebucht_betrag) / NULLIF(sum(kuerzung_betrag), 0)) AS durchsetzungsquote
FROM core.fact_kuerzung
WHERE kuerzung_betrag > 0
  AND ausgebucht_betrag IS NOT NULL   -- null ≠ 0: nur erfasste Ausbuchungen
  AND NOT ist_haftungsquote
  AND NOT ist_mwst_einbehalt
GROUP BY 1;
