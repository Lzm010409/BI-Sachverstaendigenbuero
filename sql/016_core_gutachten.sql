-- 016_core_gutachten.sql — Phase 4: fact_gutachten + BVSK/Totalschaden-Marts
--
-- Reproduzierbar aus raw, Views. Alle Beträge brutto/netto wie im Gutachten.
-- Fachwerte aus raw.gutachten_fachwerte (OneDrive-Extraktion, DSGVO-gefiltert).

-- --- fact_gutachten (Grain: ein Gutachten je Aktenzeichen) -------------------
CREATE OR REPLACE VIEW core.fact_gutachten AS
SELECT
  aktenzeichen,
  (payload->>'wiederbeschaffungswert')::numeric(12,2)   AS wiederbeschaffungswert,
  (payload->>'restwert')::numeric(12,2)                 AS restwert,
  (payload->>'wertminderung')::numeric(12,2)            AS wertminderung,
  (payload->>'reparaturkosten_netto')::numeric(12,2)    AS reparaturkosten_netto,
  (payload->>'reparaturkosten_brutto')::numeric(12,2)   AS reparaturkosten_brutto,
  (payload->>'schadenhoehe_brutto')::numeric(12,2)      AS schadenhoehe_brutto,
  (payload->>'nutzungsausfall_tagessatz')::numeric(10,2) AS nutzungsausfall_tagessatz,
  (payload->>'reparaturdauer_tage')::int                AS reparaturdauer_tage,
  payload->>'beurteilung'                               AS beurteilung,
  -- Abgeleitet (Definition mit Inhaber final zu bestätigen, plan-phase-4 §7.4):
  -- Totalschaden = Reparaturkosten (brutto) > WBW (brutto). Zusätzlich die
  -- SV-Beurteilung als autoritative Zweitquelle behalten.
  CASE
    WHEN (payload->>'reparaturkosten_brutto')::numeric IS NULL
      OR (payload->>'wiederbeschaffungswert')::numeric IS NULL THEN NULL
    ELSE (payload->>'reparaturkosten_brutto')::numeric > (payload->>'wiederbeschaffungswert')::numeric
  END                                                   AS ist_totalschaden,
  CASE
    WHEN (payload->>'reparaturkosten_brutto')::numeric IS NULL
      OR (payload->>'wiederbeschaffungswert')::numeric IS NULL THEN NULL
    ELSE (payload->>'reparaturkosten_brutto')::numeric > 1.3 * (payload->>'wiederbeschaffungswert')::numeric
  END                                                   AS ueber_130_prozent,
  extracted_at
FROM raw.gutachten_fachwerte;

-- --- marts ------------------------------------------------------------------

-- Leitfrage 8 (BVSK): Honorar (Σ Grundhonorar aus sevDesk, Phase 3) vs. Schadenhöhe
-- je Fall. Der eigentliche BVSK-Korridor-Abgleich (Tabelle) folgt separat; hier die
-- Datengrundlage: Honorar, Schadenhöhe (brutto) und WBW nebeneinander.
CREATE OR REPLACE VIEW marts.v_honorar_vs_schaden AS
WITH honorar AS (
  SELECT aktenzeichen, sum(summe_netto) AS grundhonorar_netto
  FROM core.fact_rechnungsposition
  WHERE kategorie = 'Grundhonorar' AND aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  g.aktenzeichen,
  h.grundhonorar_netto,
  g.schadenhoehe_brutto,
  g.reparaturkosten_netto,
  g.wiederbeschaffungswert,
  g.ist_totalschaden
FROM core.fact_gutachten g
LEFT JOIN honorar h ON h.aktenzeichen = g.aktenzeichen;

-- Leitfrage 10: Totalschaden-/130-%-Quote je Monat (Bezug: Ausbuchungs-/Won-Datum
-- aus fact_ausbuchung; fällt der Fall dort nicht an, greift extracted_at nicht als
-- Geschäftszeitpunkt — daher Join auf fact_ausbuchung.won_time).
CREATE OR REPLACE VIEW marts.v_totalschaden_quote AS
SELECT
  date_trunc('month', fa.won_time)::date            AS monat,
  count(*)                                            AS anzahl_gutachten,
  count(*) FILTER (WHERE g.ist_totalschaden)          AS anzahl_totalschaden,
  count(*) FILTER (WHERE g.ueber_130_prozent)         AS anzahl_ueber_130,
  round(
    count(*) FILTER (WHERE g.ist_totalschaden)::numeric
    / NULLIF(count(*), 0), 4)                         AS totalschaden_quote
FROM core.fact_gutachten g
JOIN core.fact_ausbuchung fa ON fa.aktenzeichen = g.aktenzeichen
WHERE fa.won_time IS NOT NULL
GROUP BY 1;
