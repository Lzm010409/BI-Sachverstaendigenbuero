-- 058_honorar_referenz.sql — LF8: fixture-getriebene Honorar-Referenztabellen
--
-- Bisher lag NUR die eigene Honorartabelle als hartkodierte VALUES in
-- core.dim_honorar_tabelle (sql/037). Damit ließ sich die eigene Forderung weder
-- gegen den BVSK-Korridor noch gegen das HUK-Tableau vergleichen — und die als
-- "editierbar" dokumentierte fixtures/honorartabelle.json hatte gar keinen Loader.
--
-- Diese Migration schließt beides: eine fixture-geladene Referenztabelle mit vier
-- Sichten (EIGEN, BVSK_HB_III, BVSK_HB_V, HUK) und darauf Vergleichs-Views.
--
-- Herkunft der Werte (NIE erfunden — verifizierbare Quelle, vgl. CLAUDE.md):
--   EIGEN       — AGB-Honorartabelle des Büros (identisch zu sql/037-VALUES).
--   BVSK_HB_III — BVSK-Honorarbefragung 2024, Korridorwert HB III (95 %-Perzentil).
--   BVSK_HB_V   — BVSK 2024, Korridor HB V: wert_netto = Unter-, wert_netto_max =
--                 Obergrenze des Korridors (Obergrenze entspricht dem HB-III-Wert).
--   HUK         — HUK-Coburg SV-Honorartableau (Nettobetrag). Enthält ab 1000 €
--                 Schadenhöhe eine 80-€-Nebenkostenpauschale; das reine
--                 HUK-Grundhonorar ist daher wert_netto − 80 (siehe v_honorar_vergleich).
--
-- Alle Beträge NETTO (Referenztabellen sind branchenüblich netto notiert). Der
-- Vergleich erfolgt konsequent netto gegen netto.
-- Gepflegt über fixtures/honorar_referenz.csv + etl/load-honorar-referenz.ts
-- (TRUNCATE+INSERT, voller Sync). Bei Tarif-/Befragungsänderung: CSV pflegen, neu
-- deployen. Kein neuer Migrations-Bedarf für reine Wertänderungen.

-- --- Referenztabelle (fixture-geladen) ---------------------------------------
CREATE TABLE IF NOT EXISTS core.dim_honorar_referenz (
  tabelle        text    NOT NULL
    CHECK (tabelle IN ('EIGEN', 'BVSK_HB_III', 'BVSK_HB_V', 'HUK')),
  schaden_bis    integer NOT NULL,
  wert_netto     numeric(12,2) NOT NULL,
  wert_netto_max numeric(12,2),                 -- nur BVSK_HB_V (Korridor-Obergrenze), sonst NULL
  PRIMARY KEY (tabelle, schaden_bis)
);
COMMENT ON TABLE core.dim_honorar_referenz IS
  'Honorar-Referenztabellen je Schadenstufe, netto (EIGEN/BVSK_HB_III/BVSK_HB_V/HUK). Fixture: fixtures/honorar_referenz.csv. wert_netto_max nur bei BVSK_HB_V (Korridor-Obergrenze).';

-- --- LF8: Honorar-Konformität (eigene Tabelle) -------------------------------
-- Unverändertes Spaltenschema (CREATE OR REPLACE zulässig): nur die Referenz-
-- Quelle wechselt von der hartkodierten dim_honorar_tabelle auf die fixture-
-- geladene dim_honorar_referenz (Sicht EIGEN). Ergebnis identisch, aber pflegbar.
CREATE OR REPLACE VIEW marts.v_honorar_konformitaet AS
WITH basis AS (
  SELECT aktenzeichen, ist_totalschaden,
    CASE WHEN ist_totalschaden THEN wiederbeschaffungswert
         ELSE reparaturkosten_netto + COALESCE(wertminderung,0) END AS schaden_basis
  FROM core.fact_gutachten
),
soll AS (
  SELECT b.aktenzeichen, b.ist_totalschaden, b.schaden_basis,
    (SELECT min(wert_netto) FROM core.dim_honorar_referenz t
      WHERE t.tabelle = 'EIGEN' AND t.schaden_bis >= b.schaden_basis) AS honorar_soll_netto
  FROM basis b WHERE b.schaden_basis IS NOT NULL
),
ist AS (
  SELECT aktenzeichen, sum(summe_netto) AS honorar_ist_netto
  FROM core.fact_rechnungsposition WHERE kategorie='Grundhonorar' GROUP BY aktenzeichen
)
SELECT
  s.aktenzeichen, s.ist_totalschaden,
  round(s.schaden_basis,2)                          AS schaden_basis,
  s.honorar_soll_netto,
  i.honorar_ist_netto,
  round(i.honorar_ist_netto - s.honorar_soll_netto, 2) AS abweichung_netto,
  CASE WHEN abs(i.honorar_ist_netto - s.honorar_soll_netto) <= 1 THEN 'konform'
       WHEN i.honorar_ist_netto < s.honorar_soll_netto            THEN 'unter Tabelle'
       ELSE 'über Tabelle' END                       AS befund
FROM soll s JOIN ist i USING (aktenzeichen)
WHERE s.honorar_soll_netto IS NOT NULL AND i.honorar_ist_netto > 0;

-- --- LF8: Mehrfach-Referenzvergleich je Fall ---------------------------------
-- Eine Zeile je Fall mit eigener Forderung gegenüber allen Referenzen. Basis =
-- Schadenhöhe (bei Totalschaden/130 %: WBW, sonst Reparaturkosten netto + merkantile
-- Wertminderung); maßgeblich ist stets die nächsthöhere 'bis'-Stufe der Referenz.
--   grundhonorar_netto    = fakturiertes Grundhonorar (Positionen kategorie=Grundhonorar)
--   rechnung_total_netto  = gesamte Rechnungssumme netto (alle Positionen)
-- HUK: das Tableau notiert INKL. 80-€-Nebenkostenpauschale (ab 1000 €). Für den
-- Grundhonorar-Vergleich wird sie herausgerechnet (huk_grundhonorar); für den
-- Rechnungs-Total-Vergleich bleibt der volle huk_netto stehen ("beide anzeigen").
CREATE OR REPLACE VIEW marts.v_honorar_vergleich AS
WITH basis AS (
  SELECT g.aktenzeichen, g.ist_totalschaden,
    CASE WHEN g.ist_totalschaden THEN g.wiederbeschaffungswert
         ELSE g.reparaturkosten_netto + COALESCE(g.wertminderung,0) END AS schaden_basis
  FROM core.fact_gutachten g
),
grund AS (
  SELECT aktenzeichen, sum(summe_netto) AS grundhonorar_netto
  FROM core.fact_rechnungsposition WHERE kategorie='Grundhonorar' GROUP BY aktenzeichen
),
total AS (
  SELECT aktenzeichen, sum(summe_netto) AS rechnung_total_netto
  FROM core.fact_rechnungsposition GROUP BY aktenzeichen
)
SELECT
  b.aktenzeichen,
  b.ist_totalschaden,
  round(b.schaden_basis,2)          AS schaden_basis,
  round(g.grundhonorar_netto,2)     AS grundhonorar_netto,
  round(t.rechnung_total_netto,2)   AS rechnung_total_netto,
  e.wert_netto                      AS soll_eigen,
  h3.wert_netto                     AS soll_hb3,
  hv.wert_netto                     AS hbv_low,
  hv.wert_netto_max                 AS hbv_high,
  hk.wert_netto                     AS huk_netto,
  (CASE WHEN b.schaden_basis >= 1000 THEN hk.wert_netto - 80 ELSE hk.wert_netto END) AS huk_grundhonorar,
  round(g.grundhonorar_netto - e.wert_netto,  2) AS abw_eigen,
  round(g.grundhonorar_netto - h3.wert_netto, 2) AS abw_hb3,
  CASE WHEN g.grundhonorar_netto > hv.wert_netto_max THEN 'über HB V'
       WHEN g.grundhonorar_netto < hv.wert_netto     THEN 'unter HB V'
       ELSE 'im HB-V-Korridor' END               AS lage_hbv,
  round(g.grundhonorar_netto
        - (CASE WHEN b.schaden_basis >= 1000 THEN hk.wert_netto - 80 ELSE hk.wert_netto END), 2) AS abw_huk_grund,
  round(t.rechnung_total_netto - hk.wert_netto, 2) AS abw_huk_total
FROM basis b
JOIN grund g USING (aktenzeichen)
LEFT JOIN total t USING (aktenzeichen)
LEFT JOIN LATERAL (
  SELECT wert_netto FROM core.dim_honorar_referenz
  WHERE tabelle='EIGEN' AND schaden_bis >= b.schaden_basis
  ORDER BY schaden_bis LIMIT 1) e ON true
LEFT JOIN LATERAL (
  SELECT wert_netto FROM core.dim_honorar_referenz
  WHERE tabelle='BVSK_HB_III' AND schaden_bis >= b.schaden_basis
  ORDER BY schaden_bis LIMIT 1) h3 ON true
LEFT JOIN LATERAL (
  SELECT wert_netto, wert_netto_max FROM core.dim_honorar_referenz
  WHERE tabelle='BVSK_HB_V' AND schaden_bis >= b.schaden_basis
  ORDER BY schaden_bis LIMIT 1) hv ON true
LEFT JOIN LATERAL (
  SELECT wert_netto FROM core.dim_honorar_referenz
  WHERE tabelle='HUK' AND schaden_bis >= b.schaden_basis
  ORDER BY schaden_bis LIMIT 1) hk ON true
WHERE b.schaden_basis IS NOT NULL AND g.grundhonorar_netto > 0;

-- --- LF8: Aggregat über alle verglichenen Fälle ------------------------------
-- Einordnung auf einen Blick + erwartetes HUK-Kürzungsvolumen (was die HUK bei
-- Ansatz ihres Tableaus rechnerisch kürzen würde — Total netto vs. HUK-Netto).
CREATE OR REPLACE VIEW marts.v_honorar_vergleich_summary AS
SELECT
  count(*)                                                 AS anzahl_faelle,
  round(avg(grundhonorar_netto),2)                         AS schnitt_grundhonorar,
  round(avg(soll_eigen),2)                                 AS schnitt_soll_eigen,
  round(avg(soll_hb3),2)                                   AS schnitt_hb3,
  round(avg(huk_grundhonorar),2)                           AS schnitt_huk_grundhonorar,
  -- Grundhonorar-Lage vs. eigene Tabelle
  count(*) FILTER (WHERE abs(abw_eigen) <= 1)              AS n_konform_eigen,
  count(*) FILTER (WHERE abw_eigen > 1)                    AS n_ueber_eigen,
  count(*) FILTER (WHERE abw_eigen < -1)                   AS n_unter_eigen,
  -- BVSK-HB-V-Korridor
  count(*) FILTER (WHERE lage_hbv = 'im HB-V-Korridor')    AS n_im_hbv,
  count(*) FILTER (WHERE lage_hbv = 'über HB V')           AS n_ueber_hbv,
  count(*) FILTER (WHERE lage_hbv = 'unter HB V')          AS n_unter_hbv,
  -- HUK: erwartetes Kürzungsvolumen bei Ansatz des HUK-Tableaus
  round(sum(GREATEST(rechnung_total_netto - huk_netto, 0)),2)      AS huk_kuerzungsvolumen_total,
  round(sum(GREATEST(grundhonorar_netto - huk_grundhonorar, 0)),2) AS huk_kuerzung_grundhonorar
FROM marts.v_honorar_vergleich;
