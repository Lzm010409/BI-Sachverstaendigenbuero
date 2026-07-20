-- 050_versicherer_fall_perf.sql — dim_versicherer_fall performant machen
--
-- sql/049 nutzte einen LATERAL-Join mit regexp_replace JE ZEILE über
-- raw.autoixpert_gutachten → Nested-Loop, v_versicherer_abdeckung lief in den Timeout.
-- raw.autoixpert_gutachten.aktenzeichen ist bereits normalisiert (der Extractor setzt es
-- aus dem Deal-Titel gleich wie fact_ausbuchung.aktenzeichen) → direkter Equi-Join,
-- autoiXpert-Seite vorab je Aktenzeichen dedupliziert. Ergebnis identisch, nur schnell.

CREATE OR REPLACE VIEW core.dim_versicherer_fall AS
WITH ax AS (
  SELECT DISTINCT ON (aktenzeichen)
         aktenzeichen,
         payload->'insurance'->>'organization_name' AS ins_name
  FROM raw.autoixpert_gutachten
  WHERE aktenzeichen IS NOT NULL
  ORDER BY aktenzeichen, extracted_at DESC
)
SELECT
  fa.aktenzeichen,
  COALESCE(
    core.fn_kanon_versicherer(o.name),
    core.fn_kanon_versicherer(nullif(trim(ax.ins_name), ''))
  )                                                              AS versicherer,
  CASE WHEN core.fn_kanon_versicherer(o.name) IS NOT NULL   THEN 'pipedrive'
       WHEN nullif(trim(ax.ins_name), '') IS NOT NULL       THEN 'autoixpert'
       ELSE NULL END                                            AS quelle
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_organisation o
       ON o.org_id = fa.org_id AND o.typ = 'versicherer'
LEFT JOIN ax ON ax.aktenzeichen = fa.aktenzeichen;
