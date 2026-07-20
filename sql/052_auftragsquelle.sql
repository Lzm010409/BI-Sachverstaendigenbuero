-- 052_auftragsquelle.sql — Auftragsquelle / Vermittler (LF4)
--
-- Quelle: autoiXpert report.intermediary → in raw.autoixpert_gutachten als
-- payload.intermediary.contact_id (PSEUDONYM, kein Klartext — kann natürliche Person
-- sein). Aggregation je Quelle über den Pseudonym; lesbare Namen kommen aus
-- fixtures/auftragsquellen.json (der Inhaber pflegt sie) → core.dim_auftragsquelle_label.
-- HINWEIS: zentral erst seit einigen Monaten gepflegt → Abdeckung wächst mit der Zeit;
-- historische Anreicherung (Aktenzeichen→Quelle) später separat möglich.

-- Label-Mapping (befüllt vom Loader load-auftragsquellen.ts aus der Fixture)
CREATE TABLE IF NOT EXISTS core.dim_auftragsquelle_label (
  contact_id text PRIMARY KEY,
  label      text NOT NULL
);
COMMENT ON TABLE core.dim_auftragsquelle_label IS
  'Pseudonym→Klartext-Label der Auftragsquellen (LF4). Quelle: fixtures/auftragsquellen.json.';

-- Fall → Auftragsquelle (Pseudonym), ein Datensatz je Aktenzeichen
CREATE OR REPLACE VIEW core.fact_auftragsquelle AS
SELECT DISTINCT ON (aktenzeichen)
  aktenzeichen,
  payload->'intermediary'->>'contact_id' AS intermediary_id
FROM raw.autoixpert_gutachten
WHERE aktenzeichen IS NOT NULL
  AND payload->'intermediary'->>'contact_id' IS NOT NULL
ORDER BY aktenzeichen, extracted_at DESC;

-- LF4: Auftragsquellen — Fälle, Umsatz, Durchsetzung je Quelle
CREATE OR REPLACE VIEW marts.v_auftragsquelle AS
SELECT
  COALESCE(l.label, 'Quelle ' || left(f.intermediary_id, 8)) AS quelle,
  (l.label IS NOT NULL)                                       AS benannt,
  count(*)                                                    AS anzahl_faelle,
  round(sum(fa.deal_value_brutto))                            AS summe_umsatz_brutto,
  round(avg(fa.deal_value_brutto))                            AS schnitt_umsatz_brutto,
  round(sum(fa.ausgebucht_betrag) FILTER (WHERE fa.ausgebucht_betrag > 0)) AS summe_forderungsverlust
FROM core.fact_auftragsquelle f
JOIN core.fact_ausbuchung fa USING (aktenzeichen)
LEFT JOIN core.dim_auftragsquelle_label l ON l.contact_id = f.intermediary_id
WHERE fa.won_time IS NOT NULL
GROUP BY 1, 2;

-- Abdeckung: für wie viele won-Fälle ist überhaupt eine Auftragsquelle bekannt?
CREATE OR REPLACE VIEW marts.v_auftragsquelle_abdeckung AS
SELECT
  count(*)                                                    AS won_faelle,
  count(f.intermediary_id)                                   AS mit_quelle,
  round(100.0 * count(f.intermediary_id) / NULLIF(count(*), 0), 0) AS abdeckung_pct,
  count(DISTINCT f.intermediary_id)                          AS anzahl_quellen
FROM core.fact_ausbuchung fa
LEFT JOIN core.fact_auftragsquelle f USING (aktenzeichen)
WHERE fa.won_time IS NOT NULL;
