-- 028_marts_durchsetzung_belastbar.sql — Durchsetzungsquote ehrlich machen
--
-- Problem (Datenqualität): Die Durchsetzungsquote = 1 − Ausbuchung / Kürzung.
-- Die Ausbuchung stammt aus den Forderungsverlust-Belegen (fact_forderungsverlust).
-- Fehlte ein Beleg, wurde die Ausbuchung bisher zu 0 gecoalesced → Quote = 100 %.
-- Das verletzt den Grundsatz `null ≠ 0`: „kein Beleg gefunden" ist NICHT
-- „nichts verloren". Für die 27 Vor-Pipedrive-Altfälle (2019–2024) kann per
-- Definition gar kein Beleg existieren → ihr 100 % war ein reines Artefakt.
--
-- Fix: Die Ausbuchung ist nur dann BEKANNT, wenn der Fall abgeschlossen ist, d. h.
-- `won` in core.fact_ausbuchung (Domänenregel: won_time = Ausbuchungsdatum, bei
-- Abschluss final). Nur solche Fälle liefern eine belastbare Quote; alle anderen
-- fließen NICHT in die Quote ein (bleiben aber mit ihrem Kürzungsbetrag in
-- marts.v_kuerzung_echt_je_versicherer sichtbar). Alle Beträge brutto.

-- === ECHT (Kürzungsbetrag aus Schreiben) — nur abgeschlossene Fälle ==========
CREATE OR REPLACE VIEW marts.v_durchsetzung_echt AS
WITH kuerzung AS (
  SELECT aktenzeichen,
         max(versicherer)      AS versicherer,
         sum(kuerzungsbetrag)  AS kuerzung
  FROM core.fact_kuerzungsereignis
  WHERE kuerzungsbetrag > 0
  GROUP BY aktenzeichen
),
ausbuchung AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
),
-- Belastbar: Kürzungsfall ist in fact_ausbuchung mit won_time (Ausgang final).
belastbar AS (
  SELECT k.aktenzeichen,
         COALESCE(NULLIF(trim(k.versicherer), ''), '(unbekannt)') AS versicherer,
         k.kuerzung,
         COALESCE(a.ausbuchung, 0)                                AS ausbuchung
  FROM kuerzung k
  JOIN core.fact_ausbuchung fa
    ON fa.aktenzeichen = k.aktenzeichen AND fa.won_time IS NOT NULL
  LEFT JOIN ausbuchung a ON a.aktenzeichen = k.aktenzeichen
)
SELECT
  versicherer,
  count(*)                                                     AS anzahl_faelle,
  sum(kuerzung)                                                AS summe_kuerzung,
  sum(ausbuchung)                                              AS summe_ausbuchung,
  sum(kuerzung) - sum(ausbuchung)                              AS summe_durchgesetzt,
  round(1 - sum(ausbuchung) / NULLIF(sum(kuerzung), 0), 4)     AS durchsetzungsquote
FROM belastbar
GROUP BY 1;

-- === sevDesk-Methode (fakturiert − gezahlt_sv) — nur belastbar & konsistent ==
-- Zusätzliche Filter gegenüber sql/021: nur `won` (Ausbuchung final), gezahlt_sv>0
-- (0 = Lese-Verdacht), Kürzung > 1 € (Bagatelle raus) und Ausbuchung ≤ Kürzung
-- (Quell-Inkonsistenzen wie Ausbuchung > berechnete Kürzung raus → keine Negativ-
-- Quoten mehr). So ist die durchsetzungsquote immer ein sauberer Wert in (0,1].
CREATE OR REPLACE VIEW marts.v_durchsetzung_sevdesk AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto)::numeric AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
),
won AS (
  SELECT aktenzeichen, bool_or(won_time IS NOT NULL) AS ist_won
  FROM core.fact_ausbuchung
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
JOIN won w        ON w.aktenzeichen = k.aktenzeichen
LEFT JOIN fv      ON fv.aktenzeichen = k.aktenzeichen
WHERE k.plausibel
  AND w.ist_won
  AND k.gezahlt_sv > 0
  AND k.kuerzung_berechnet > 1
  AND COALESCE(fv.ausbuchung, 0) <= k.kuerzung_berechnet;

-- === Diagnose: warum ein Schreiben (nicht) verwertbar ist ====================
-- Erweitert um die neuen Befunde (won offen, gezahlt_sv=0, inkonsistent).
CREATE OR REPLACE VIEW marts.v_kuerzung_sevdesk_diagnose AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto)::numeric AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
),
won AS (
  SELECT aktenzeichen, bool_or(won_time IS NOT NULL) AS ist_won
  FROM core.fact_ausbuchung
  GROUP BY aktenzeichen
)
SELECT
  k.aktenzeichen,
  k.versicherer,
  k.fakturiert,
  k.gezahlt_sv,
  k.kuerzung_berechnet,
  k.brief_datum,
  k.plausibel,
  CASE
    WHEN k.fakturiert IS NULL                              THEN 'kein sevDesk-Fall (Vor-Pipedrive-Altfall)'
    WHEN NOT COALESCE(w.ist_won, false)                    THEN 'noch nicht abgeschlossen (won offen)'
    WHEN k.gezahlt_sv > k.fakturiert                       THEN 'gezahlt > fakturiert — Brief vermutlich falsch gelesen'
    WHEN k.gezahlt_sv = 0                                  THEN 'gezahlt_sv = 0 — Lese-Verdacht'
    WHEN COALESCE(fv.ausbuchung, 0) > k.kuerzung_berechnet THEN 'inkonsistent: Ausbuchung > Kürzung'
    WHEN k.kuerzung_berechnet <= 1                         THEN 'voll gezahlt, keine Kürzung'
    ELSE 'verwertbar'
  END AS befund
FROM marts.v_kuerzung_sevdesk k
LEFT JOIN won w  ON w.aktenzeichen = k.aktenzeichen
LEFT JOIN fv     ON fv.aktenzeichen = k.aktenzeichen;
