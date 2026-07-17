-- 021_marts_durchsetzung_sevdesk.sql — Durchsetzungsquote + Diagnose
--
-- Echte Durchsetzung je Fall: berechnete Kürzung (fakturiert − gezahlt_sv,
-- sql/020) vs. tatsächlich ausgebuchter Forderungsverlust. Nur plausible Fälle
-- mit Kürzung > 0. Division defensiv als ::numeric.

CREATE OR REPLACE VIEW marts.v_durchsetzung_sevdesk AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto)::numeric AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  k.aktenzeichen,
  k.versicherer,
  k.fakturiert,
  k.gezahlt_sv,
  k.kuerzung_berechnet,
  COALESCE(fv.ausbuchung, 0)                                                   AS ausgebucht,
  k.kuerzung_berechnet - COALESCE(fv.ausbuchung, 0)                            AS durchgesetzt,
  round(1 - COALESCE(fv.ausbuchung, 0) / NULLIF(k.kuerzung_berechnet, 0), 4)   AS durchsetzungsquote
FROM marts.v_kuerzung_sevdesk k
LEFT JOIN fv ON fv.aktenzeichen = k.aktenzeichen
WHERE k.plausibel AND k.kuerzung_berechnet > 0;

-- Diagnose: ALLE Schreiben inkl. unplausibler (gezahlt>fakturiert, fehlende
-- sevDesk-Zuordnung) — erste Anlaufstelle, um Fehl-Lesungen nachzubessern.
CREATE OR REPLACE VIEW marts.v_kuerzung_sevdesk_diagnose AS
SELECT
  k.*,
  CASE
    WHEN k.fakturiert IS NULL         THEN 'kein sevDesk-Fall (z. B. vor SEVDESK_SINCE)'
    WHEN k.gezahlt_sv > k.fakturiert  THEN 'gezahlt > fakturiert — Brief vermutlich falsch gelesen'
    WHEN k.kuerzung_berechnet = 0     THEN 'voll gezahlt, keine Kürzung'
    ELSE 'ok'
  END AS befund
FROM marts.v_kuerzung_sevdesk k;
