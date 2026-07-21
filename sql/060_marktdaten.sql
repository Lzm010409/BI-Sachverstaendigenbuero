-- 060_marktdaten.sql — Expansions-Analyse: Marktausschöpfung je Kreis (LF7-Ausbau)
--
-- Der Geo-Layer (dim_fall_geo, sql/027/042/043) zeigt den EIGENEN Umsatz je PLZ-Gebiet,
-- aber nichts zum Normieren. Für die Expansionsfrage "wo ist viel Markt, den wir NICHT
-- abdecken?" fehlt das Marktpotenzial je Region. Diese Migration ergänzt es auf
-- Kreisebene (amtlicher Gemeindeschlüssel).
--
-- Zwei fixture-geladene Dimensionen (etl/load-marktdaten.ts):
--   dim_markt_kreis  — Kreis + amtliche Marktkennzahlen (Kfz-Bestand, Einwohner, Unfälle)
--   dim_plz4_kreis   — Brücke 4-stellige PLZ -> Kreis (Postgeographie, editierbar)
--
-- WICHTIG (CLAUDE.md): die Marktkennzahlen sind AMTLICH zu befüllen (KBA FZ1,
-- IT.NRW/Destatis) und bleiben sonst NULL — nie schätzen. Die Views funktionieren auch
-- bei leeren Kennzahlen: der EIGENE Fußabdruck je Kreis ist sofort da, die
-- Ausschöpfungsquoten erscheinen, sobald die Marktzahlen hinterlegt sind.

CREATE TABLE IF NOT EXISTS core.dim_markt_kreis (
  ags             text    PRIMARY KEY,     -- Amtlicher Gemeindeschlüssel (Kreisebene)
  kreis           text    NOT NULL,
  bundesland      text,
  einwohner       integer,                 -- Destatis/IT.NRW; NULL bis amtlich befüllt
  kfz_bestand     integer,                 -- KBA FZ1; NULL bis amtlich befüllt
  unfaelle_gesamt integer,                 -- Destatis/IT.NRW; NULL bis amtlich befüllt
  jahr            integer,
  quelle          text
);
COMMENT ON TABLE core.dim_markt_kreis IS
  'Einzugsgebiet-Kreise + amtliche Marktkennzahlen (Kfz-Bestand/Einwohner/Unfälle). Fixture: fixtures/markt_kreis.csv. Kennzahlen amtlich zu befüllen (KBA/Destatis), nie geschätzt.';

CREATE TABLE IF NOT EXISTS core.dim_plz4_kreis (
  plz4  text PRIMARY KEY,
  ags   text NOT NULL
);
COMMENT ON TABLE core.dim_plz4_kreis IS
  'Zuordnung 4-stellige PLZ -> Kreis (ags). Fixture: fixtures/plz4_kreis.csv. Deterministische Postgeographie, editierbar.';

-- --- Eigener Fußabdruck je Kreis (immer verfügbar, inkl. Außerhalb-Bucket) ----------
-- Grain: ein Kreis (bzw. '(außerhalb Einzugsgebiet)'). Nur won-Fälle (realisierter Umsatz).
CREATE OR REPLACE VIEW marts.v_markt_kreis_footprint AS
SELECT
  COALESCE(m.kreis, '(außerhalb Einzugsgebiet)')                         AS kreis,
  pk.ags,
  count(*) FILTER (WHERE fa.won_time IS NOT NULL)                        AS eigene_faelle,
  round(sum(fa.deal_value_brutto) FILTER (WHERE fa.won_time IS NOT NULL)) AS eigener_umsatz_brutto
FROM core.fact_ausbuchung fa
JOIN core.dim_fall_geo g USING (aktenzeichen)
LEFT JOIN core.dim_plz4_kreis pk ON pk.plz4 = g.plz4
LEFT JOIN core.dim_markt_kreis m ON m.ags = pk.ags
GROUP BY 1, 2
ORDER BY eigene_faelle DESC;

-- --- Marktausschöpfung je Kreis (LF7-Expansion) -------------------------------------
-- Eigene Fälle/Umsatz gegen Marktgröße. Quoten sind NULL, solange die Marktkennzahl
-- fehlt (Division durch NULLIF) — kein Scheinwert. Zeigt umgekehrt auch Kreise mit
-- Markt aber (fast) ohne eigene Fälle = Expansionslücken.
CREATE OR REPLACE VIEW marts.v_marktausschoepfung AS
WITH eigen AS (
  SELECT
    pk.ags,
    count(*) FILTER (WHERE fa.won_time IS NOT NULL)                        AS eigene_faelle,
    round(sum(fa.deal_value_brutto) FILTER (WHERE fa.won_time IS NOT NULL)) AS eigener_umsatz_brutto
  FROM core.fact_ausbuchung fa
  JOIN core.dim_fall_geo g USING (aktenzeichen)
  JOIN core.dim_plz4_kreis pk ON pk.plz4 = g.plz4
  GROUP BY pk.ags
)
SELECT
  m.ags, m.kreis, m.bundesland,
  m.einwohner, m.kfz_bestand, m.unfaelle_gesamt, m.jahr, m.quelle,
  COALESCE(e.eigene_faelle, 0)         AS eigene_faelle,
  COALESCE(e.eigener_umsatz_brutto, 0) AS eigener_umsatz_brutto,
  -- Ausschöpfung: eigene Fälle je 10.000 Kfz und je 1.000 Unfälle (nur mit Marktzahl)
  round(10000.0 * COALESCE(e.eigene_faelle, 0) / NULLIF(m.kfz_bestand, 0), 2)     AS faelle_je_10k_kfz,
  round(1000.0  * COALESCE(e.eigene_faelle, 0) / NULLIF(m.unfaelle_gesamt, 0), 2) AS faelle_je_1k_unfaelle
FROM core.dim_markt_kreis m
LEFT JOIN eigen e ON e.ags = m.ags
ORDER BY eigene_faelle DESC;
