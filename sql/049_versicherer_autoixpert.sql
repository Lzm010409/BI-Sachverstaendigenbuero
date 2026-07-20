-- 049_versicherer_autoixpert.sql — Versicherer-Lücke (LF2) über autoiXpert schließen
--
-- Pipedrive `deal.org_id` (Versicherer) ist nur zu ~75 % befüllt. autoiXpert liefert
-- den Versicherer je Report als `insurance.organization_name` (juristische Person,
-- DSGVO-unkritisch) — geladen von etl/autoixpert/extract-gutachten.ts nach
-- raw.autoixpert_gutachten. Diese Migration:
--   1) die Marken-Kanonisierung aus sql/035 als WIEDERVERWENDBARE Funktion,
--   2) dim_versicherer_kanon auf die Funktion umgestellt (eine Quelle der Wahrheit),
--   3) dim_versicherer_fall = bester Versicherer je Fall (Pipedrive, sonst autoiXpert),
--   4) v_versicherer_abdeckung = Abdeckung vorher (nur Pipedrive) vs. mit Fallback.
-- Die bestehenden Versicherer-Views bleiben vorerst auf org_id → dim_versicherer_kanon;
-- Umstellung auf dim_versicherer_fall erst NACH Verifikation der autoiXpert-Datenqualität.

-- 1) Kanonisierung als Funktion (identische Regeln wie sql/035).
CREATE OR REPLACE FUNCTION core.fn_kanon_versicherer(n text) RETURNS text AS $$
  SELECT CASE
    WHEN n ~* 'provinzial'                THEN 'Provinzial'
    WHEN n ~* 'huk'                        THEN 'HUK-COBURG'
    WHEN n ~* 'allianz'                    THEN 'Allianz'
    WHEN n ~* 'adac'                       THEN 'ADAC'
    WHEN n ~* '\maioi\M|\maloi\M|nissay'   THEN 'Aioi Nissay Dowa'
    WHEN n ~* '\maxa\M'                    THEN 'AXA'
    WHEN n ~* 'devk'                       THEN 'DEVK'
    WHEN n ~* '\mlvm\M'                    THEN 'LVM'
    WHEN n ~* 'cosmos'                     THEN 'CosmosDirekt'
    WHEN n ~* 'continentale'               THEN 'Continentale'
    WHEN n ~* 'general'                    THEN 'Generali'
    WHEN n ~* 'barmenia'                   THEN 'Barmenia'
    WHEN n ~* 'gothaer'                    THEN 'Gothaer'
    WHEN n ~* '\mhdi\M'                    THEN 'HDI'
    WHEN n ~* 'zurich'                     THEN 'Zurich'
    WHEN n ~* 'verti'                      THEN 'Verti'
    WHEN n ~* '\mvhv\M'                    THEN 'VHV'
    WHEN n ~* 'volkswagen|^vw |vw$'        THEN 'Volkswagen'
    WHEN n ~* 'kravag'                     THEN 'KRAVAG'
    WHEN n ~* 'debeka'                     THEN 'DEBEKA'
    WHEN n ~* 'ergo'                       THEN 'ERGO'
    WHEN n ~* '\maig\M'                    THEN 'AIG'
    WHEN n ~* 'europa'                     THEN 'Europa'
    WHEN n ~* 'baloise|basler'             THEN 'Baloise'
    WHEN n ~* 'signal *iduna'              THEN 'Signal Iduna'
    WHEN n ~* 'nürnberger|nuernberger'     THEN 'NÜRNBERGER'
    WHEN n ~* 'württembergische|wuerttembergische' THEN 'Württembergische'
    WHEN n ~* '\mwgv\M'                    THEN 'WGV'
    WHEN n ~* 'r\+v'                       THEN 'R+V'
    WHEN n ~* 'admiral'                    THEN 'AdmiralDirekt'
    WHEN n ~* 'neo *digital'               THEN 'Neodigital'
    WHEN n ~* 'da *direkt'                 THEN 'DA Direkt'
    WHEN n ~* 'sparkass|s-?direkt'         THEN 'Sparkassen Direkt'
    WHEN n ~* 'alte *leipziger'            THEN 'Alte Leipziger'
    WHEN n ~* 'concordia'                  THEN 'Concordia'
    WHEN n ~* 'mecklenburg'                THEN 'Mecklenburgische'
    WHEN n ~* 'rhion|rheinland'            THEN 'RheinLand'
    WHEN n ~* 'itzehoer'                   THEN 'Itzehoer'
    WHEN n ~* 'fahrlehrer'                 THEN 'Fahrlehrer'
    WHEN n ~* 'toyota'                     THEN 'Toyota'
    ELSE nullif(trim(n), '')
  END
$$ LANGUAGE sql IMMUTABLE;

-- 2) dim_versicherer_kanon auf die Funktion umstellen (Verhalten unverändert).
CREATE OR REPLACE VIEW core.dim_versicherer_kanon AS
SELECT org_id, name AS name_roh, core.fn_kanon_versicherer(name) AS versicherer
FROM core.dim_organisation
WHERE typ = 'versicherer';

-- 3) Bester Versicherer je Fall: Pipedrive-Verknüpfung, sonst autoiXpert-Insurance.
CREATE OR REPLACE VIEW core.dim_versicherer_fall AS
SELECT
  fa.aktenzeichen,
  COALESCE(
    core.fn_kanon_versicherer(o.name),
    core.fn_kanon_versicherer(nullif(trim(ax.ins_name), ''))
  )                                                                     AS versicherer,
  CASE WHEN core.fn_kanon_versicherer(o.name) IS NOT NULL         THEN 'pipedrive'
       WHEN nullif(trim(ax.ins_name), '') IS NOT NULL             THEN 'autoixpert'
       ELSE NULL END                                                   AS quelle
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_organisation o
       ON o.org_id = fa.org_id AND o.typ = 'versicherer'
LEFT JOIN LATERAL (
  SELECT payload->'insurance'->>'organization_name' AS ins_name
  FROM raw.autoixpert_gutachten a
  WHERE upper(regexp_replace(a.aktenzeichen, '\s', '', 'g')) = fa.aktenzeichen
  ORDER BY a.extracted_at DESC
  LIMIT 1
) ax ON true;

-- 4) Abdeckung vorher/nachher (nur won-Fälle).
CREATE OR REPLACE VIEW marts.v_versicherer_abdeckung AS
SELECT
  count(*)                                                              AS won_faelle,
  count(vk.versicherer)                                                 AS nur_pipedrive,
  count(vf.versicherer)                                                 AS mit_autoixpert,
  round(100.0 * count(vk.versicherer) / NULLIF(count(*), 0), 0)         AS pct_pipedrive,
  round(100.0 * count(vf.versicherer) / NULLIF(count(*), 0), 0)         AS pct_gesamt,
  count(*) FILTER (WHERE vf.quelle = 'autoixpert')                      AS neu_durch_autoixpert
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_versicherer_kanon vk ON vk.org_id = fa.org_id
LEFT JOIN core.dim_versicherer_fall  vf ON vf.aktenzeichen = fa.aktenzeichen
WHERE fa.won_time IS NOT NULL;
