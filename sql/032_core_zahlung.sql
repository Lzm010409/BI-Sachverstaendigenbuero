-- 032_core_zahlung.sql — Kürzung & Durchsetzung aus dem sevDesk-Zahlungsverlauf
--
-- Inhaber-Modell (ersetzt die OCR-Kürzung aus den Schreiben): die ECHTE Kürzung ist
-- die Kombination aus Rechnungssumme, initialer (evtl. gekürzter) Zahlung und
-- späterer Ausbuchung — alles als Buchungen je Rechnung in sevDesk sichtbar:
--   - „Geschäftskonto Postbank" (Konto 1100) = Zahlungseingang
--   - „Ausgebuchte Rechnungen" (Konto 1203) = Ausbuchung (Verlust)
-- Domänenregeln (CLAUDE.md): brutto, null≠0, Kürzung≠Ausbuchung, USt-Einbehalt ist
-- keine Kürzung. Nur GESCHLOSSENE Fälle (won) sind belastbar.

-- --- fact_zahlung: eine Buchung (Grain: CheckAccountTransactionLog) --------------
CREATE OR REPLACE VIEW core.fact_zahlung AS
SELECT
  (b.payload->>'log_id')::bigint            AS log_id,
  b.invoice_id,
  (b.payload->>'amount')::numeric(12,2)     AS betrag,
  (b.payload->>'booking_date')::timestamptz AS buchungsdatum,
  b.payload->>'konto_name'                  AS konto_name,
  b.payload->>'konto_nr'                    AS konto_nr,
  CASE
    WHEN b.payload->>'konto_name' ILIKE '%ausgebuch%' OR b.payload->>'konto_nr' = '1203'
      THEN 'ausbuchung'
    ELSE 'zahlung'
  END                                       AS buchungstyp
FROM raw.sevdesk_invoice_bookings b;

-- --- fact_rechnung_zahlung: je Rechnung verdichtet -----------------------------
CREATE OR REPLACE VIEW core.fact_rechnung_zahlung AS
WITH inv AS (
  SELECT
    id                                                          AS invoice_id,
    (payload->>'sumGross')::numeric(12,2)                       AS rechnung_brutto,
    (payload->>'sumTax')::numeric(12,2)                         AS rechnung_mwst,
    substring(upper(regexp_replace(payload->>'invoiceNumber','\s','','g')) FROM '\d{4}/\d+TG') AS aktenzeichen
  FROM raw.sevdesk_invoices
),
zahl AS (
  SELECT invoice_id,
         sum(betrag)                                              AS gezahlt_gesamt,
         (array_agg(betrag ORDER BY buchungsdatum, log_id))[1]    AS erste_zahlung,
         min(buchungsdatum)                                       AS erste_zahlung_datum
  FROM core.fact_zahlung WHERE buchungstyp = 'zahlung' GROUP BY invoice_id
),
ausb AS (
  SELECT invoice_id, sum(betrag) AS ausgebucht
  FROM core.fact_zahlung WHERE buchungstyp = 'ausbuchung' GROUP BY invoice_id
)
SELECT
  inv.invoice_id,
  inv.aktenzeichen,
  inv.rechnung_brutto,
  inv.rechnung_mwst,
  COALESCE(zahl.gezahlt_gesamt, 0)                    AS gezahlt_gesamt,
  zahl.erste_zahlung,
  zahl.erste_zahlung_datum,
  COALESCE(ausb.ausgebucht, 0)                        AS ausgebucht,
  -- Kürzung = Rechnung − erste (evtl. gekürzte) Zahlung. NULL wenn nie gezahlt.
  round(inv.rechnung_brutto - zahl.erste_zahlung, 2)  AS kuerzung,
  -- USt-Einbehalt: „Kürzung" ≈ MwSt der Rechnung → kein echter Abzug (Vorsteuer).
  (zahl.erste_zahlung IS NOT NULL
     AND abs((inv.rechnung_brutto - zahl.erste_zahlung) - inv.rechnung_mwst) <= 0.05) AS ist_mwst_einbehalt
FROM inv
LEFT JOIN zahl ON zahl.invoice_id = inv.invoice_id
LEFT JOIN ausb ON ausb.invoice_id = inv.invoice_id;

-- --- marts: Zahlungsverlauf je Fall (operative Zeitleiste) ---------------------
CREATE OR REPLACE VIEW marts.v_zahlungsverlauf AS
SELECT
  rz.aktenzeichen,
  z.buchungsdatum,
  z.buchungstyp,
  z.betrag,
  z.konto_name
FROM core.fact_zahlung z
JOIN core.fact_rechnung_zahlung rz ON rz.invoice_id = z.invoice_id
WHERE rz.aktenzeichen IS NOT NULL;

-- --- marts: Durchsetzung je Fall (zahlungsbasiert, nur won & echte Kürzung) -----
CREATE OR REPLACE VIEW marts.v_durchsetzung_zahlung AS
WITH per_az AS (
  SELECT
    aktenzeichen,
    sum(rechnung_brutto)            AS rechnung_brutto,
    sum(erste_zahlung)              AS erste_zahlung,
    sum(gezahlt_gesamt)             AS gezahlt_gesamt,
    sum(ausgebucht)                 AS ausgebucht,
    sum(kuerzung)                   AS kuerzung,
    bool_and(ist_mwst_einbehalt)    AS ist_mwst_einbehalt,
    min(erste_zahlung_datum)        AS erste_zahlung_datum
  FROM core.fact_rechnung_zahlung
  WHERE aktenzeichen IS NOT NULL AND erste_zahlung IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  p.aktenzeichen,
  COALESCE(NULLIF(trim(vo.name), ''), '(unbekannt)') AS versicherer,
  aw.name                                            AS anwalt,
  COALESCE(g.grund, '(offen)')                       AS kuerzungsgrund,
  p.rechnung_brutto,
  p.erste_zahlung,
  p.gezahlt_gesamt,
  p.ausgebucht,
  p.kuerzung,
  p.kuerzung - p.ausgebucht                          AS durchgesetzt,
  round(1 - p.ausgebucht / NULLIF(p.kuerzung, 0), 4) AS durchsetzungsquote,
  p.erste_zahlung_datum
FROM per_az p
JOIN core.fact_ausbuchung fa ON fa.aktenzeichen = p.aktenzeichen AND fa.won_time IS NOT NULL
LEFT JOIN core.dim_organisation vo ON vo.org_id = fa.org_id AND vo.typ = 'versicherer'
LEFT JOIN core.dim_organisation aw ON aw.org_id = fa.anwalt_org_id
LEFT JOIN core.dim_ausbuchungsgrund g ON g.grund_id = fa.ausgebucht_grund_id
-- Haftungsquote/Teilschuld (Grund 71) ist KEINE Kürzung (CLAUDE.md) → raus.
WHERE p.kuerzung > 1
  AND NOT p.ist_mwst_einbehalt
  AND COALESCE(fa.ausgebucht_grund_id, 0) <> 71;

-- --- marts: Kürzung je Grund (LF2 „aus welchem Grund") — aus Pipedrive-Ausbuchungsgrund
CREATE OR REPLACE VIEW marts.v_kuerzung_zahlung_je_grund AS
SELECT
  kuerzungsgrund,
  count(*)                 AS anzahl_faelle,
  round(sum(kuerzung), 2)  AS summe_kuerzung,
  round(sum(ausgebucht),2) AS summe_ausbuchung
FROM marts.v_durchsetzung_zahlung
GROUP BY 1;

-- --- marts: Durchsetzung/Kürzung je Versicherer (zahlungsbasiert) --------------
CREATE OR REPLACE VIEW marts.v_durchsetzung_zahlung_je_versicherer AS
SELECT
  versicherer,
  count(*)                                              AS anzahl_faelle,
  round(sum(kuerzung), 2)                               AS summe_kuerzung,
  round(sum(ausgebucht), 2)                             AS summe_ausbuchung,
  round(1 - sum(ausgebucht) / NULLIF(sum(kuerzung), 0), 4) AS durchsetzungsquote
FROM marts.v_durchsetzung_zahlung
GROUP BY versicherer;

-- --- marts: Durchsetzung/Kürzung je Anwalt (zahlungsbasiert) -------------------
CREATE OR REPLACE VIEW marts.v_durchsetzung_zahlung_je_anwalt AS
SELECT
  COALESCE(anwalt, '(kein Anwalt erfasst)')             AS anwalt,
  count(*)                                              AS anzahl_faelle,
  round(sum(kuerzung), 2)                               AS summe_kuerzung,
  round(sum(ausgebucht), 2)                             AS summe_ausbuchung,
  round(1 - sum(ausgebucht) / NULLIF(sum(kuerzung), 0), 4) AS durchsetzungsquote
FROM marts.v_durchsetzung_zahlung
GROUP BY 1;
