-- 003_core.sql — core als Views über raw (Phase 2)
--
-- Reproduzierbar aus raw, kein Transform-Schritt, kein dbt. Typisierung per Cast.
-- DSGVO: es werden NUR die unten selektierten Pfade übernommen; Kennzeichen und
-- Freitexte bleiben in raw und tauchen in core nicht auf.
--
-- Custom-Field-Hashes (Quelle: docs/field-mapping.json):
--   8e0a… enthaltene MwSt (monetary {value})   c4ae… Ausgebucht Betrag (monetary {value})
--   a037… Ausgebucht Grund (enum {id,label})   d886… sevDesk-Rechnungs-ID (varchar)

-- --- fact_ausbuchung (Grain: ein Deal mit gültigem Aktenzeichen) ------------
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
  -- ausgebucht_betrag: NULL bleibt NULL (≠ 0). 0 = "geprüft, voll bezahlt".
  (b.payload->'custom_fields'->'c4ae5d687eacc0bbe5c05a1d70ec447644d4eb3f'->>'value')::numeric(12,2) AS ausgebucht_betrag,
  (b.payload->'custom_fields'->'a037653e87dd01a3ab9946c9741ff2db41de64f3'->>'id')::int             AS ausgebucht_grund_id,
  (b.payload->'custom_fields'->'c4ae5d687eacc0bbe5c05a1d70ec447644d4eb3f'->>'value') IS NOT NULL    AS ist_erfasst,
  (b.payload->>'won_time')::timestamptz                                      AS won_time,
  (b.payload->>'add_time')::timestamptz                                      AS add_time,
  b.payload->>'status'                                                       AS status,
  (b.payload->>'org_id')::bigint                                             AS org_id,
  b.payload->'custom_fields'->>'d8863fcbcb97aeb225a9418261b5508c0410783f'    AS sevdesk_rechnung_id
FROM b
WHERE b.aktenzeichen ~ '^\d{4}/\d+TG$';

-- --- _rejects: ungültige Aktenzeichen sichtbar machen, nicht still verwerfen -
CREATE OR REPLACE VIEW core._rejects AS
SELECT
  id AS deal_id,
  payload->>'title'          AS roh_titel,
  'aktenzeichen_ungueltig'   AS grund
FROM raw.pipedrive_deals
WHERE upper(regexp_replace(payload->>'title', '\s', '', 'g')) !~ '^\d{4}/\d+TG$';

-- --- dim_organisation: Name + Typ aus label_ids (35=Versicherer, 32=Auftraggeber)
CREATE OR REPLACE VIEW core.dim_organisation AS
SELECT
  id AS org_id,
  payload->>'name' AS name,
  CASE
    WHEN (payload->'label_ids') @> '35'::jsonb THEN 'versicherer'
    WHEN (payload->'label_ids') @> '32'::jsonb THEN 'auftraggeber'
    ELSE 'unbekannt'
  END AS typ
FROM raw.pipedrive_organizations;

-- --- dim_ausbuchungsgrund: aus der Optionsliste (nicht hartkodiert) ----------
CREATE OR REPLACE VIEW core.dim_ausbuchungsgrund AS
SELECT DISTINCT
  (payload->'custom_fields'->'a037653e87dd01a3ab9946c9741ff2db41de64f3'->>'id')::int AS grund_id,
  payload->'custom_fields'->'a037653e87dd01a3ab9946c9741ff2db41de64f3'->>'label'     AS grund
FROM raw.pipedrive_deals
WHERE payload->'custom_fields'->'a037653e87dd01a3ab9946c9741ff2db41de64f3'->>'id' IS NOT NULL;

-- --- dim_datum: Kalenderachse -----------------------------------------------
CREATE OR REPLACE VIEW core.dim_datum AS
SELECT
  d::date                          AS datum,
  extract(year   FROM d)::int      AS jahr,
  extract(month  FROM d)::int      AS monat,
  to_char(d, 'YYYY-MM')            AS jahr_monat,
  extract(quarter FROM d)::int     AS quartal,
  extract(isodow FROM d)::int      AS wochentag
FROM generate_series(date '2023-01-01', date '2030-12-31', interval '1 day') d;
