-- 063_marktkontext_nrw.sql — NRW-Landesaggregate als grober Markt-Headroom
--
-- Der Inhaber lieferte zwei amtliche Quellen (IT.NRW/KBA Kfz-Bestand, Polizeiliche
-- Verkehrsunfallbilanz NRW). Beide sind LANDESWEIT, kein Kreis-Breakdown — sie füllen
-- daher NICHT dim_markt_kreis (das bleibt offen, bis per-Zulassungsbezirk-/per-Kreis-
-- Tabellen vorliegen), sondern geben nur den groben NRW-Kontext: wie klein ist der
-- eigene Fußabdruck gegenüber dem Gesamtmarkt.
--
-- Bewusst NUR als Landeskontext ausgewiesen — der Anteil "eigene Fälle / NRW-Unfälle"
-- ist KEINE echte Marktausschöpfung (das Büro bedient nur wenige Kreise), sondern eine
-- Größenordnung fürs Expansions-Gespräch. Fixture: fixtures/markt_nrw.csv.

CREATE TABLE IF NOT EXISTS core.dim_markt_nrw (
  kennzahl text    NOT NULL,
  jahr     integer NOT NULL,
  wert     numeric NOT NULL,
  quelle   text,
  PRIMARY KEY (kennzahl, jahr)
);
COMMENT ON TABLE core.dim_markt_nrw IS
  'NRW-Landesaggregate (Kfz-/Pkw-Bestand, Verkehrsunfälle) als grober Marktkontext. Fixture: fixtures/markt_nrw.csv. KEIN Kreis-Breakdown.';

-- Grober NRW-Marktkontext: eigenes Fallvolumen gegen NRW-Gesamtgrößen.
-- faelle_2025 vs. NRW-Unfälle 2025 (gleicher Zeitraum); Kfz/Pkw als stehender Bestand.
CREATE OR REPLACE VIEW marts.v_marktkontext_nrw AS
WITH b AS (
  SELECT
    count(*) FILTER (WHERE won_time >= '2025-01-01' AND won_time < '2026-01-01') AS faelle_2025,
    count(*) FILTER (WHERE won_time IS NOT NULL)                                 AS faelle_gesamt
  FROM core.fact_ausbuchung
),
n AS (
  SELECT
    max(wert) FILTER (WHERE kennzahl = 'verkehrsunfaelle_nrw') AS unfaelle_nrw,
    max(wert) FILTER (WHERE kennzahl = 'kfz_bestand_nrw')      AS kfz_nrw,
    max(wert) FILTER (WHERE kennzahl = 'pkw_bestand_nrw')      AS pkw_nrw
  FROM core.dim_markt_nrw
)
SELECT
  n.unfaelle_nrw,
  n.kfz_nrw,
  n.pkw_nrw,
  b.faelle_2025,
  b.faelle_gesamt,
  -- Größenordnung, KEINE echte Ausschöpfung (nur wenige Kreise bedient):
  round(1000000.0 * b.faelle_2025 / NULLIF(n.unfaelle_nrw, 0), 1) AS faelle_je_mio_nrw_unfaelle_2025,
  round(100.0 * b.faelle_2025 / NULLIF(n.unfaelle_nrw, 0), 4)     AS anteil_nrw_unfaelle_pct_2025
FROM b CROSS JOIN n;
