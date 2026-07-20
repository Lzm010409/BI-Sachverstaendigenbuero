-- 055_rechnungsposition_dedup.sql — Positions-Dublette beheben
--
-- Befund aus dem Validierungs-Sweep: core.fact_rechnungsposition lieferte für
-- einzelne Rechnungen doppelte Positionszeilen (7 Extra-Zeilen, v. a. Rechnung
-- 100427984 / Aktenzeichen 0625/1636TG: 7 Positionen -> 14 Zeilen).
--
-- Ursache: der Join `LEFT JOIN core.fact_ausbuchung fa ON fa.sevdesk_rechnung_id
-- = p.invoice_id` fächert auf, wenn ZWEI Deals dieselbe sevDesk-Rechnung
-- referenzieren (hier: 0625/1636TG hat zwei Deals, 704 und 712). Der Join dient
-- nur der Herleitung des Aktenzeichens — er darf die Positionsmenge nicht
-- vervielfachen. Fix: als LATERAL … LIMIT 1, damit je Position genau ein
-- Aktenzeichen (und genau eine Zeile) entsteht. Beide Dubletten-Deals tragen
-- dasselbe Aktenzeichen, daher ist die Auswahl inhaltlich eindeutig.
--
-- Hinweis (Quelldaten): der doppelte Deal 0625/1636TG sollte in Pipedrive
-- zusammengeführt/entfernt werden — das ist die eigentliche Datenpflege. Diese
-- View-Korrektur macht das Warehouse aber unabhängig davon robust.
--
-- Spaltenschnitt unverändert gegenüber 008 -> CREATE OR REPLACE ist zulässig.

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
-- Aktenzeichen dedupliziert herleiten: genau ein Deal je Rechnung, kein Fan-out.
LEFT JOIN LATERAL (
  SELECT f.aktenzeichen
  FROM core.fact_ausbuchung f
  WHERE f.sevdesk_rechnung_id = p.invoice_id::text
  ORDER BY f.aktenzeichen
  LIMIT 1
) fa ON true
LEFT JOIN LATERAL (
  SELECT r.kategorie
  FROM core.dim_positionskategorie_regel r
  WHERE p.payload->>'name'          ILIKE r.muster
     OR p.payload->'part'->>'name'  ILIKE r.muster
  ORDER BY r.prioritaet, r.id
  LIMIT 1
) k ON true;
