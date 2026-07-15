-- 006_core_sevdesk.sql — core/marts über die sevDesk-Positionen (Phase 3)
--
-- Reproduzierbar aus raw, kein Transform-Schritt, kein dbt. Typisierung per Cast.
-- Alle Beträge brutto/netto wie von sevDesk geliefert (keine Umrechnung).
-- Grain fact_rechnungsposition: eine sevDesk-InvoicePos.
--
-- Join zum Aktenzeichen zweistufig (robust, da Pipedrive-Feld d886 dünn befüllt
-- sein kann):
--   1) primär: fact_ausbuchung.sevdesk_rechnung_id (Pipedrive) == Invoice-Objekt-ID
--   2) Fallback: Aktenzeichen-Präfix aus invoiceNumber (Format MMJJ/NummerTG…).

-- --- fact_rechnungsposition -------------------------------------------------
CREATE OR REPLACE VIEW core.fact_rechnungsposition AS
WITH pos AS (
  SELECT id AS position_id, invoice_id, payload FROM raw.sevdesk_invoice_positions
),
inv AS (
  SELECT id AS invoice_id, payload FROM raw.sevdesk_invoices
)
SELECT
  p.position_id,
  p.invoice_id,
  i.payload->>'invoiceNumber'                              AS rechnungsnummer,
  -- Aktenzeichen: Deal-Join zuerst, sonst aus der Rechnungsnummer ableiten.
  COALESCE(
    fa.aktenzeichen,
    substring(i.payload->>'invoiceNumber' FROM '^\d{4}/\d+TG')
  )                                                        AS aktenzeichen,
  (i.payload->>'invoiceDate')::timestamptz                 AS rechnungsdatum,
  NULLIF(p.payload->>'positionNumber', '')::int            AS position_nr,
  p.payload->>'name'                                       AS position_name,
  p.payload->'part'->>'partNumber'                         AS part_nummer,
  p.payload->'part'->>'name'                               AS part_name,
  (p.payload->'part'->'category'->>'id')::int              AS part_category_id,
  -- Kontrollierter Kategorienkatalog (datengetrieben: neue Namen -> 'Sonstiges').
  -- Signal primär Positions-name, sekundär part_name. MIT DEM INHABER ABZUSTIMMEN.
  CASE
    WHEN p.payload->>'name' ILIKE 'SV-Honorar%'      OR p.payload->'part'->>'name' ILIKE 'SV-Honorar%'      THEN 'Grundhonorar'
    WHEN p.payload->>'name' ILIKE 'Fahrtkosten%'     OR p.payload->'part'->>'name' ILIKE 'Fahrtkosten%'     THEN 'Fahrtkosten'
    WHEN p.payload->>'name' ILIKE 'Lichtbild%'       OR p.payload->>'name' ILIKE 'Foto%'                    THEN 'Fotokosten'
    WHEN p.payload->>'name' ILIKE 'Porto%'           OR p.payload->>'name' ILIKE '%Telefon%'                THEN 'Porto/Telefon'
    WHEN p.payload->>'name' ILIKE 'Schreibkost%'                                                            THEN 'Schreibkosten'
    WHEN p.payload->>'name' ILIKE 'EDV%'                                                                    THEN 'EDV-Kosten'
    WHEN p.payload->>'name' ILIKE 'Restwert%'        OR p.payload->'part'->>'name' ILIKE 'Restwert%'        THEN 'Restwertermittlung'
    WHEN p.payload->>'name' ILIKE 'Bewertungsabfrage%' OR p.payload->'part'->>'name' ILIKE 'Bewertungsabfrage%' THEN 'Bewertungsabfrage'
    WHEN p.payload->>'name' ILIKE 'Schichtdickenmess%'                                                      THEN 'Schichtdickenmessung'
    ELSE 'Sonstiges'
  END                                                      AS kategorie,
  (p.payload->>'quantity')::numeric(12,4)                  AS menge,
  p.payload->'unity'->>'name'                              AS einheit,
  p.payload->'unity'->>'translationCode'                   AS einheit_code,
  (p.payload->>'priceGross')::numeric(12,4)                AS einzelpreis_brutto,
  (p.payload->>'priceNet')::numeric(12,4)                  AS einzelpreis_netto,
  (p.payload->>'sumGross')::numeric(12,2)                  AS summe_brutto,
  (p.payload->>'sumNet')::numeric(12,2)                    AS summe_netto,
  (p.payload->>'sumTax')::numeric(12,2)                    AS summe_steuer,
  (p.payload->>'taxRate')::numeric(5,2)                    AS steuersatz
FROM pos p
JOIN inv i ON i.invoice_id = p.invoice_id
LEFT JOIN core.fact_ausbuchung fa ON fa.sevdesk_rechnung_id = p.invoice_id::text;

-- --- dim_positionskategorie: datengetriebene Mapping-/Prüftabelle ------------
-- Zeigt je Roh-Positionsname, auf welche Kategorie er abbildet. Unkartierte Namen
-- erscheinen als 'Sonstiges' und sind damit sofort sichtbar (Katalog-Review).
CREATE OR REPLACE VIEW core.dim_positionskategorie AS
SELECT DISTINCT
  kategorie,
  position_name,
  part_nummer,
  part_name
FROM core.fact_rechnungsposition;

-- --- marts ------------------------------------------------------------------

-- Positionen je Monat und Kategorie (Rechnungs-Soll, nicht Zahlung).
CREATE OR REPLACE VIEW marts.v_rechnungsposition_monat AS
SELECT
  date_trunc('month', rechnungsdatum)::date  AS monat,
  kategorie,
  count(*)                                    AS anzahl_positionen,
  count(DISTINCT invoice_id)                  AS anzahl_rechnungen,
  sum(summe_brutto)                           AS summe_brutto,
  sum(summe_netto)                            AS summe_netto
FROM core.fact_rechnungsposition
WHERE rechnungsdatum IS NOT NULL
GROUP BY 1, 2;

-- Kategorie-Anteile über den Gesamtzeitraum.
CREATE OR REPLACE VIEW marts.v_position_je_kategorie AS
SELECT
  kategorie,
  count(*)                                    AS anzahl_positionen,
  sum(summe_brutto)                           AS summe_brutto,
  sum(summe_brutto) / NULLIF(sum(sum(summe_brutto)) OVER (), 0) AS anteil_brutto
FROM core.fact_rechnungsposition
GROUP BY 1;

-- Konsistenz: Summe der Positionen (brutto) vs. Rechnungssumme (brutto).
-- Erwartung (an einer echten Rechnung bestätigt): Differenz == 0.
CREATE OR REPLACE VIEW marts.v_rechnung_konsistenz AS
SELECT
  i.id                                        AS invoice_id,
  i.payload->>'invoiceNumber'                 AS rechnungsnummer,
  (i.payload->>'sumGross')::numeric(12,2)     AS rechnung_brutto,
  COALESCE(sum((p.payload->>'sumGross')::numeric), 0)::numeric(12,2) AS positionen_brutto,
  ((i.payload->>'sumGross')::numeric
     - COALESCE(sum((p.payload->>'sumGross')::numeric), 0))::numeric(12,2) AS differenz
FROM raw.sevdesk_invoices i
LEFT JOIN raw.sevdesk_invoice_positions p ON p.invoice_id = i.id
GROUP BY 1, 2, 3;
