-- 059_honorar_vergleich_fix.sql — Korrektur der HB-V-Lage bei Schäden über Tabellengrenze
--
-- In sql/058 fiel die lage_hbv-CASE für Fälle OHNE passende Referenzstufe (Schaden
-- > 50 000 €, oberhalb der BVSK/HUK-Tableaus) auf den ELSE-Zweig durch und labelte sie
-- fälschlich als 'im HB-V-Korridor' — die Korridorgrenzen sind dort aber NULL, ein
-- Vergleich ist gar nicht möglich. Das ist genau der Fehlermodus "plausibel-aber-falsch".
--
-- Fix: eigener Zweig 'außerhalb Tabelle', wenn keine HB-V-Stufe greift. Diese Fälle
-- werden damit weder als im/über/unter Korridor gezählt. Summary bekommt dafür die
-- Spalte n_ausserhalb_hbv (am Ende angehängt → CREATE OR REPLACE zulässig).
-- Restliche Logik unverändert gegenüber 058.

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
  CASE WHEN hv.wert_netto IS NULL                    THEN 'außerhalb Tabelle'
       WHEN g.grundhonorar_netto > hv.wert_netto_max THEN 'über HB V'
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

CREATE OR REPLACE VIEW marts.v_honorar_vergleich_summary AS
SELECT
  count(*)                                                 AS anzahl_faelle,
  round(avg(grundhonorar_netto),2)                         AS schnitt_grundhonorar,
  round(avg(soll_eigen),2)                                 AS schnitt_soll_eigen,
  round(avg(soll_hb3),2)                                   AS schnitt_hb3,
  round(avg(huk_grundhonorar),2)                           AS schnitt_huk_grundhonorar,
  count(*) FILTER (WHERE abs(abw_eigen) <= 1)              AS n_konform_eigen,
  count(*) FILTER (WHERE abw_eigen > 1)                    AS n_ueber_eigen,
  count(*) FILTER (WHERE abw_eigen < -1)                   AS n_unter_eigen,
  count(*) FILTER (WHERE lage_hbv = 'im HB-V-Korridor')    AS n_im_hbv,
  count(*) FILTER (WHERE lage_hbv = 'über HB V')           AS n_ueber_hbv,
  count(*) FILTER (WHERE lage_hbv = 'unter HB V')          AS n_unter_hbv,
  round(sum(GREATEST(rechnung_total_netto - huk_netto, 0)),2)      AS huk_kuerzungsvolumen_total,
  round(sum(GREATEST(grundhonorar_netto - huk_grundhonorar, 0)),2) AS huk_kuerzung_grundhonorar,
  count(*) FILTER (WHERE lage_hbv = 'außerhalb Tabelle')   AS n_ausserhalb_hbv
FROM marts.v_honorar_vergleich;
