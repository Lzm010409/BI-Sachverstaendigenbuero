-- 057_rechnungsposition_perf.sql — Performance-Fix für core.fact_rechnungsposition
--
-- 055 hat die Positions-Dublette per `LEFT JOIN LATERAL (… LIMIT 1)` behoben — korrekt,
-- aber teuer: der LATERAL scannt fact_ausbuchung (Regex über alle Deals + NOT-EXISTS-
-- Filter aus 056) EINMAL JE POSITION (~6700x, Nested Loop). Dadurch liefen alle Views
-- über fact_rechnungsposition (Positions-Umsatz, Deckungsbeitrag …) in Timeouts.
--
-- Fix: den Aktenzeichen-Lookup EINMAL vorab je Rechnung aggregieren (min(aktenzeichen)
-- je sevdesk_rechnung_id) und dann als normalen Hash-Equi-Join anschließen. Weiterhin
-- 1:1 (kein Fan-out wie vor 055), aber statt ~6700 Einzel-Scans nur ein Aggregat-Scan.
-- Spaltenschnitt unverändert -> CREATE OR REPLACE zulässig.

CREATE OR REPLACE VIEW core.fact_rechnungsposition AS
WITH pos AS (
  SELECT id AS position_id, invoice_id, payload FROM raw.sevdesk_invoice_positions
),
inv AS (
  SELECT id AS invoice_id, payload FROM raw.sevdesk_invoices
),
-- Genau ein Aktenzeichen je Rechnung (dedupliziert, kein Fan-out bei doppelten Deals).
az AS (
  SELECT sevdesk_rechnung_id, min(aktenzeichen) AS aktenzeichen
  FROM core.fact_ausbuchung
  WHERE sevdesk_rechnung_id IS NOT NULL
  GROUP BY sevdesk_rechnung_id
)
SELECT
  p.position_id,
  p.invoice_id,
  i.payload->>'invoiceNumber'                              AS rechnungsnummer,
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
  COALESCE(k.kategorie, 'Sonstiges')                       AS kategorie,
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
LEFT JOIN az fa ON fa.sevdesk_rechnung_id = p.invoice_id::text
LEFT JOIN LATERAL (
  SELECT r.kategorie
  FROM core.dim_positionskategorie_regel r
  WHERE p.payload->>'name'          ILIKE r.muster
     OR p.payload->'part'->>'name'  ILIKE r.muster
  ORDER BY r.prioritaet, r.id
  LIMIT 1
) k ON true;
