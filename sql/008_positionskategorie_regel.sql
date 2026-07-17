-- 008_positionskategorie_regel.sql — editierbarer Kategorien-Katalog (Phase 3)
--
-- Loest den fest verdrahteten CASE-Block aus 006 durch eine Regeltabelle ab. So
-- pflegt der Inhaber Kategorien, ohne SQL anzufassen: Quelle der Wahrheit ist
-- fixtures/positionskategorie.json, das bei jedem Deploy per
-- etl/sevdesk/load-kategorien.ts in diese Tabelle gespiegelt wird (Datei editieren
-- -> redeploy). Direkte Aenderungen an der Tabelle werden beim naechsten Deploy
-- ueberschrieben; die JSON-Datei ist massgeblich.
--
-- Matching: ILIKE-Muster gegen Positions-name ODER part_name; bei mehreren Treffern
-- gewinnt die niedrigste prioritaet (first match), sonst 'Sonstiges'.

CREATE TABLE IF NOT EXISTS core.dim_positionskategorie_regel (
  id         bigserial PRIMARY KEY,
  muster     text NOT NULL,                 -- SQL ILIKE-Muster (z. B. 'Fahrtkosten%')
  kategorie  text NOT NULL,
  prioritaet int  NOT NULL DEFAULT 100      -- kleiner = hoehere Prioritaet
);
GRANT SELECT ON core.dim_positionskategorie_regel TO metabase_ro;

-- fact_rechnungsposition: Kategorie regelbasiert (first match), Fallback 'Sonstiges'.
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
LEFT JOIN core.fact_ausbuchung fa ON fa.sevdesk_rechnung_id = p.invoice_id::text
LEFT JOIN LATERAL (
  SELECT r.kategorie
  FROM core.dim_positionskategorie_regel r
  WHERE p.payload->>'name'          ILIKE r.muster
     OR p.payload->'part'->>'name'  ILIKE r.muster
  ORDER BY r.prioritaet, r.id
  LIMIT 1
) k ON true;
