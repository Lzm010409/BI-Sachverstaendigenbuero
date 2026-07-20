-- 053_auftragsquelle_historisch.sql — historische Auftragsquellen + vereinheitlichte Sicht
--
-- autoiXpert-intermediary deckt NUR ab 2026 ab (zentral erst seither gepflegt). Die
-- Altfälle kommen aus der Excel/CSV des Inhabers (fixtures/auftragsquellen_historisch.csv
-- → core.dim_auftragsquelle_historisch, Klartext-Quelle je Aktenzeichen). v_auftragsquelle
-- vereinheitlicht beide Quellen: pro Fall gilt historisch (Klartext) vor autoiXpert
-- (benannt), sonst der Pseudonym; sonst '(unbekannt)'.

CREATE TABLE IF NOT EXISTS core.dim_auftragsquelle_historisch (
  aktenzeichen text PRIMARY KEY,
  quelle       text NOT NULL
);
COMMENT ON TABLE core.dim_auftragsquelle_historisch IS
  'Historische Auftragsquelle je Aktenzeichen (Klartext, Inhaber-Excel). Quelle: fixtures/auftragsquellen_historisch.csv.';

-- Vereinheitlichte LF4-Sicht über beide Quellen
CREATE OR REPLACE VIEW marts.v_auftragsquelle AS
WITH je_fall AS (
  SELECT
    fa.aktenzeichen,
    COALESCE(
      h.quelle,                                                             -- historisch (Klartext)
      l.label,                                                              -- autoiXpert benannt
      CASE WHEN f.intermediary_id IS NOT NULL
           THEN 'Quelle ' || left(f.intermediary_id, 8) END                -- autoiXpert Pseudonym
    )                                                                       AS quelle,
    fa.deal_value_brutto,
    fa.ausgebucht_betrag
  FROM core.fact_ausbuchung fa
  LEFT JOIN core.fact_auftragsquelle          f USING (aktenzeichen)
  LEFT JOIN core.dim_auftragsquelle_label     l ON l.contact_id = f.intermediary_id
  LEFT JOIN core.dim_auftragsquelle_historisch h USING (aktenzeichen)
  WHERE fa.won_time IS NOT NULL
)
SELECT
  COALESCE(quelle, '(unbekannt)')                                          AS quelle,
  (quelle IS NOT NULL)                                                     AS benannt,
  count(*)                                                                 AS anzahl_faelle,
  round(sum(deal_value_brutto))                                           AS summe_umsatz_brutto,
  round(avg(deal_value_brutto))                                           AS schnitt_umsatz_brutto,
  round(sum(ausgebucht_betrag) FILTER (WHERE ausgebucht_betrag > 0))       AS summe_forderungsverlust
FROM je_fall
GROUP BY 1, 2;

-- Abdeckung über beide Quellen
CREATE OR REPLACE VIEW marts.v_auftragsquelle_abdeckung AS
SELECT
  count(*)                                                                 AS won_faelle,
  count(*) FILTER (WHERE h.aktenzeichen IS NOT NULL OR f.intermediary_id IS NOT NULL) AS mit_quelle,
  round(100.0 * count(*) FILTER (WHERE h.aktenzeichen IS NOT NULL OR f.intermediary_id IS NOT NULL)
        / NULLIF(count(*), 0), 0)                                          AS abdeckung_pct,
  count(*) FILTER (WHERE h.aktenzeichen IS NOT NULL)                       AS aus_historik,
  count(*) FILTER (WHERE h.aktenzeichen IS NULL AND f.intermediary_id IS NOT NULL) AS aus_autoixpert
FROM core.fact_ausbuchung fa
LEFT JOIN core.fact_auftragsquelle          f USING (aktenzeichen)
LEFT JOIN core.dim_auftragsquelle_historisch h USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL;
