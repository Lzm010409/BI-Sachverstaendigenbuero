-- 020_marts_kuerzung_sevdesk.sql — echte Kürzung = fakturiert − gezahlt_sv
--
-- Ein Schreiben je Fall. Fakturierte SV-Kosten aus fact_ausbuchung
-- (deal_value_brutto = Rechnungssumme brutto, deckungsgleich mit den sevDesk-
-- Positionen). `plausibel` = Fall in sevDesk vorhanden UND gezahlt ≤ fakturiert
-- (fängt Fehl-Lesungen des Briefs ab, z. B. gezahlt > fakturiert).

CREATE OR REPLACE VIEW marts.v_kuerzung_sevdesk AS
WITH brief AS (
  SELECT aktenzeichen,
         max(versicherer)       AS versicherer,
         max(sv_kosten_gezahlt) AS gezahlt_sv,
         max(datum)             AS brief_datum
  FROM core.fact_kuerzungsereignis
  WHERE sv_kosten_gezahlt IS NOT NULL
  GROUP BY aktenzeichen
),
fakt AS (
  SELECT aktenzeichen, max(deal_value_brutto) AS fakturiert
  FROM core.fact_ausbuchung
  GROUP BY aktenzeichen
)
SELECT
  b.aktenzeichen,
  b.versicherer,
  f.fakturiert,
  b.gezahlt_sv,
  round((f.fakturiert - b.gezahlt_sv)::numeric, 2)              AS kuerzung_berechnet,
  b.brief_datum,
  (f.fakturiert IS NOT NULL AND b.gezahlt_sv <= f.fakturiert)   AS plausibel
FROM brief b
LEFT JOIN fakt f USING (aktenzeichen);
