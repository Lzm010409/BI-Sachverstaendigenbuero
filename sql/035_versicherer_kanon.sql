-- 035_versicherer_kanon.sql — Versicherer-Namen kanonisieren
--
-- Die Pipedrive-Org-Namen der Versicherer sind stark dubliziert (158 Rohnamen, z. B.
-- „HUK" / „HUK Coburg Vers. AG" / „HUK24 AG"; „ALLIANZ" / „Allianz Versicherung AG").
-- Das zersplittert jede Auswertung je Versicherer. dim_versicherer_kanon bildet den
-- Rohnamen per Namensmuster auf eine Marke ab; unbekannte Namen bleiben unverändert.
-- Reihenfolge im CASE ist relevant (spezifisch vor generisch). Zum Pflegen/Ergänzen:
-- hier eine WHEN-Zeile hinzufügen und neu deployen.

CREATE OR REPLACE VIEW core.dim_versicherer_kanon AS
SELECT
  org_id,
  name AS name_roh,
  CASE
    WHEN name ~* 'provinzial'                THEN 'Provinzial'
    WHEN name ~* 'huk'                        THEN 'HUK-COBURG'
    WHEN name ~* 'allianz'                    THEN 'Allianz'
    WHEN name ~* 'adac'                       THEN 'ADAC'
    WHEN name ~* '\maioi\M|\maloi\M|nissay'   THEN 'Aioi Nissay Dowa'
    WHEN name ~* '\maxa\M'                    THEN 'AXA'
    WHEN name ~* 'devk'                       THEN 'DEVK'
    WHEN name ~* '\mlvm\M'                    THEN 'LVM'
    WHEN name ~* 'cosmos'                     THEN 'CosmosDirekt'
    WHEN name ~* 'continentale'               THEN 'Continentale'
    WHEN name ~* 'general'                    THEN 'Generali'
    WHEN name ~* 'barmenia'                   THEN 'Barmenia'
    WHEN name ~* 'gothaer'                    THEN 'Gothaer'
    WHEN name ~* '\mhdi\M'                    THEN 'HDI'
    WHEN name ~* 'zurich'                     THEN 'Zurich'
    WHEN name ~* 'verti'                      THEN 'Verti'
    WHEN name ~* '\mvhv\M'                    THEN 'VHV'
    WHEN name ~* 'volkswagen|^vw |vw$'        THEN 'Volkswagen'
    WHEN name ~* 'kravag'                     THEN 'KRAVAG'
    WHEN name ~* 'debeka'                     THEN 'DEBEKA'
    WHEN name ~* 'ergo'                       THEN 'ERGO'
    WHEN name ~* '\maig\M'                    THEN 'AIG'
    WHEN name ~* 'europa'                     THEN 'Europa'
    WHEN name ~* 'baloise|basler'             THEN 'Baloise'
    WHEN name ~* 'signal *iduna'              THEN 'Signal Iduna'
    WHEN name ~* 'nürnberger|nuernberger'     THEN 'NÜRNBERGER'
    WHEN name ~* 'württembergische|wuerttembergische' THEN 'Württembergische'
    WHEN name ~* '\mwgv\M'                    THEN 'WGV'
    WHEN name ~* 'r\+v'                       THEN 'R+V'
    WHEN name ~* 'admiral'                    THEN 'AdmiralDirekt'
    WHEN name ~* 'neo *digital'               THEN 'Neodigital'
    WHEN name ~* 'da *direkt'                 THEN 'DA Direkt'
    WHEN name ~* 'sparkass|s-?direkt'         THEN 'Sparkassen Direkt'
    WHEN name ~* 'alte *leipziger'            THEN 'Alte Leipziger'
    WHEN name ~* 'concordia'                  THEN 'Concordia'
    WHEN name ~* 'mecklenburg'                THEN 'Mecklenburgische'
    WHEN name ~* 'rhion|rheinland'            THEN 'RheinLand'
    WHEN name ~* 'itzehoer'                   THEN 'Itzehoer'
    WHEN name ~* 'fahrlehrer'                 THEN 'Fahrlehrer'
    WHEN name ~* 'toyota'                     THEN 'Toyota'
    ELSE trim(name)
  END AS versicherer
FROM core.dim_organisation
WHERE typ = 'versicherer';

-- === Versicherer-Views auf den kanonischen Namen umstellen =====================

-- v_durchsetzung_zahlung (perf-CTE aus sql/034 beibehalten, Name kanonisiert)
CREATE OR REPLACE VIEW marts.v_durchsetzung_zahlung AS
WITH per_az AS (
  SELECT
    aktenzeichen,
    sum(rechnung_brutto)            AS rechnung_brutto,
    sum(erste_zahlung)              AS erste_zahlung,
    sum(gezahlt_gesamt)             AS gezahlt_gesamt,
    sum(ausgebucht)                 AS ausgebucht,
    sum(kuerzung)                   AS kuerzung,
    bool_and(ist_mwst_einbehalt)    AS ist_mwst_einbehalt,
    min(erste_zahlung_datum)        AS erste_zahlung_datum
  FROM core.fact_rechnung_zahlung
  WHERE aktenzeichen IS NOT NULL AND erste_zahlung IS NOT NULL
  GROUP BY aktenzeichen
),
fa AS MATERIALIZED (
  SELECT aktenzeichen, org_id, anwalt_org_id, ausgebucht_grund_id
  FROM core.fact_ausbuchung
  WHERE won_time IS NOT NULL
)
SELECT
  p.aktenzeichen,
  COALESCE(vk.versicherer, '(unbekannt)')            AS versicherer,
  aw.name                                            AS anwalt,
  COALESCE(g.grund, '(offen)')                       AS kuerzungsgrund,
  p.rechnung_brutto,
  p.erste_zahlung,
  p.gezahlt_gesamt,
  p.ausgebucht,
  p.kuerzung,
  p.kuerzung - p.ausgebucht                          AS durchgesetzt,
  round(1 - p.ausgebucht / NULLIF(p.kuerzung, 0), 4) AS durchsetzungsquote,
  p.erste_zahlung_datum
FROM per_az p
JOIN fa                            ON fa.aktenzeichen = p.aktenzeichen
LEFT JOIN core.dim_versicherer_kanon vk ON vk.org_id = fa.org_id
LEFT JOIN core.dim_organisation aw  ON aw.org_id = fa.anwalt_org_id
LEFT JOIN core.dim_ausbuchungsgrund g ON g.grund_id = fa.ausgebucht_grund_id
WHERE p.kuerzung > 1
  AND NOT p.ist_mwst_einbehalt
  AND COALESCE(fa.ausgebucht_grund_id, 0) <> 71;

-- v_forderungsverlust_je_versicherer (LF5) — kanonisiert
CREATE OR REPLACE VIEW marts.v_forderungsverlust_je_versicherer AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  COALESCE(vk.versicherer, '(unbekannt)') AS versicherer,
  count(*)                                AS anzahl_faelle,
  sum(fv.ausbuchung)                      AS summe_ausbuchung,
  round(avg(fv.ausbuchung), 2)            AS schnitt_ausbuchung
FROM fv
LEFT JOIN core.fact_ausbuchung fa ON fa.aktenzeichen = fv.aktenzeichen
LEFT JOIN core.dim_versicherer_kanon vk ON vk.org_id = fa.org_id
GROUP BY 1;

-- v_versicherer_x_anwalt — kanonisiert
CREATE OR REPLACE VIEW marts.v_versicherer_x_anwalt AS
SELECT
  COALESCE(vk.versicherer, '(kein/unbekannter Versicherer)') AS versicherer,
  COALESCE(da.anwalt, '(unbekannt)')                         AS anwalt,
  count(*)                                                   AS anzahl_faelle,
  sum(fa.deal_value_brutto)                                  AS summe_fakturiert_brutto
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_versicherer_kanon vk ON vk.org_id = fa.org_id
LEFT JOIN core.dim_anwalt da ON da.anwalt_org_id = fa.anwalt_org_id
WHERE fa.anwalt_org_id IS NOT NULL OR fa.org_id IS NOT NULL
GROUP BY 1, 2;
