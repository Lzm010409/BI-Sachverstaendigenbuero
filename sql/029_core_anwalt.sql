-- 029_core_anwalt.sql — Rechtsanwalt/Kanzlei als eigene Dimension (LF4)
--
-- Befund (Inhaber): der Rechtsanwalt je Fall steht im Deal-Custom-Field
-- `215832fc…` — die Feld-Doku hatte es fälschlich als „Nutzungsausfall Tagessatz"
-- geraten (docs/field-mapping.md korrigieren). Der Feldwert ist die **org_id der
-- Kanzlei** (Fremdschlüssel auf dieselbe dim_organisation wie der Versicherer).
-- Damit wird Versicherer × Anwalt kreuzbar: `deal.org_id` = Versicherer,
-- `custom_fields[215832fc]` = Anwalt.
--
-- DSGVO: Kanzleien sind juristische Personen (Klartext erlaubt). Das Feld zeigt nur
-- auf Kanzleien; zur Sicherheit gibt dim_anwalt NUR Namen mit Kanzlei-Markern frei
-- (Rechtsanw/Anwalt/Kanzlei/Partner/PartG/mbB/GbR/„& „/„ und "), damit keine
-- natürliche Person geleakt wird, falls das Feld je fehlgepflegt auf eine Privat-
-- Org zeigt. Beträge brutto.

-- --- fact_ausbuchung: um anwalt_org_id erweitern (Spalte am Ende angehängt) -----
CREATE OR REPLACE VIEW core.fact_ausbuchung AS
WITH b AS (
  SELECT
    id AS deal_id,
    payload,
    upper(regexp_replace(payload->>'title', '\s', '', 'g')) AS aktenzeichen
  FROM raw.pipedrive_deals
)
SELECT
  b.aktenzeichen,
  b.deal_id,
  (b.payload->>'value')::numeric(12,2)                                       AS deal_value_brutto,
  (b.payload->'custom_fields'->'8e0a4e9266683b1a80cb216ab073e7c106fe85de'->>'value')::numeric(12,2) AS enthaltene_mwst,
  (b.payload->'custom_fields'->'c4ae5d687eacc0bbe5c05a1d70ec447644d4eb3f'->>'value')::numeric(12,2) AS ausgebucht_betrag,
  (b.payload->'custom_fields'->'a037653e87dd01a3ab9946c9741ff2db41de64f3'->>'id')::int             AS ausgebucht_grund_id,
  (b.payload->'custom_fields'->'c4ae5d687eacc0bbe5c05a1d70ec447644d4eb3f'->>'value') IS NOT NULL    AS ist_erfasst,
  (b.payload->>'won_time')::timestamptz                                      AS won_time,
  (b.payload->>'add_time')::timestamptz                                      AS add_time,
  b.payload->>'status'                                                       AS status,
  (b.payload->>'org_id')::bigint                                             AS org_id,
  b.payload->'custom_fields'->>'d8863fcbcb97aeb225a9418261b5508c0410783f'    AS sevdesk_rechnung_id,
  -- NEU: Rechtsanwalt/Kanzlei (org_id der Kanzlei; NULL = ohne Anwalt / nicht erfasst)
  (b.payload->'custom_fields'->>'215832fc2c61f065e6ad134c2a46485911fdcf28')::bigint AS anwalt_org_id
FROM b
WHERE b.aktenzeichen ~ '^\d{4}/\d+TG$';

-- --- dim_anwalt: Kanzleien (juristische Personen), DSGVO-Whitelist per Namensmuster
CREATE OR REPLACE VIEW core.dim_anwalt AS
SELECT
  org_id AS anwalt_org_id,
  name   AS anwalt
FROM core.dim_organisation
WHERE name ~* '(rechtsanw|anwält|anwalt|kanzlei| & | und |partner|partg|mbb|gbr)';

-- --- marts.v_anwalt (LF4): bringt Umsatz UND zahlt zuverlässig? ---------------
-- Je Kanzlei: Fallzahl, won-Fälle, fakturierter Umsatz, tatsächlicher
-- Forderungsverlust (Ausbuchung aus fact_forderungsverlust). Nur Fälle mit Anwalt.
CREATE OR REPLACE VIEW marts.v_anwalt AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausbuchung
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  COALESCE(da.anwalt, '(ohne Kanzlei-Kennung)')        AS anwalt,
  count(*)                                             AS anzahl_faelle,
  count(*) FILTER (WHERE fa.won_time IS NOT NULL)      AS anzahl_won,
  sum(fa.deal_value_brutto)                            AS summe_fakturiert_brutto,
  round(avg(fa.deal_value_brutto), 2)                  AS schnitt_fakturiert_brutto,
  COALESCE(sum(fv.ausbuchung), 0)                      AS summe_forderungsverlust
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_anwalt        da ON da.anwalt_org_id = fa.anwalt_org_id
LEFT JOIN fv                        ON fv.aktenzeichen  = fa.aktenzeichen
WHERE fa.anwalt_org_id IS NOT NULL
GROUP BY 1;

-- --- marts.v_versicherer_x_anwalt: die Kreuzdimension -------------------------
-- Fälle & Umsatz je (Versicherer, Anwalt). Versicherer = deal.org_id (Pipedrive-
-- Org), Anwalt = anwalt_org_id. Beide über dieselbe Org-Dimension aufgelöst.
CREATE OR REPLACE VIEW marts.v_versicherer_x_anwalt AS
SELECT
  COALESCE(NULLIF(trim(vo.name), ''), '(kein/unbekannter Versicherer)') AS versicherer,
  COALESCE(da.anwalt, '(ohne Kanzlei-Kennung)')                         AS anwalt,
  count(*)                                                              AS anzahl_faelle,
  sum(fa.deal_value_brutto)                                             AS summe_fakturiert_brutto
FROM core.fact_ausbuchung fa
LEFT JOIN core.dim_organisation vo ON vo.org_id = fa.org_id AND vo.typ = 'versicherer'
LEFT JOIN core.dim_anwalt       da ON da.anwalt_org_id = fa.anwalt_org_id
WHERE fa.anwalt_org_id IS NOT NULL OR fa.org_id IS NOT NULL
GROUP BY 1, 2;
