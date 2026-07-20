-- 056_deleted_deals.sql — in Pipedrive gelöschte Deals abgleichen (Tombstone)
--
-- Problem: der Deal-Import ist inkrementell + reines Upsert (kein Delete). Wird ein
-- Deal in Pipedrive gelöscht, NACHDEM er importiert wurde, liefert die API ihn nicht
-- mehr -> er bleibt als Karteileiche in raw.pipedrive_deals und verfälscht Kennzahlen.
--
-- Lösung ohne "Rohdaten heilig" zu verletzen: raw.pipedrive_deals wird NICHT gelöscht.
-- Stattdessen führt etl/pipedrive/extract-deleted-deals.ts einen Grabstein-Log
-- (raw.pipedrive_deal_deleted) über die per `status=deleted` gemeldeten IDs (rollendes
-- 30-Tage-Fenster von Pipedrive; wir sammeln dauerhaft, Upsert entfernt nie). Die
-- Fakten schließen diese IDs aus -> gelöschte Deals verschwinden aus allen Auswertungen,
-- die Rohdaten bleiben reproduzierbar erhalten.

-- --- Grabstein-Tabelle (append/upsert, nie löschen) -------------------------
CREATE TABLE IF NOT EXISTS raw.pipedrive_deal_deleted (
  id           bigint PRIMARY KEY,
  payload      jsonb NOT NULL,
  extracted_at timestamptz NOT NULL DEFAULT now()   -- erstmals als gelöscht erkannt
);
COMMENT ON TABLE raw.pipedrive_deal_deleted IS
  'Grabstein-Log der in Pipedrive gelöschten Deal-IDs (status=deleted). Wird von den Fakten ausgeschlossen; raw.pipedrive_deals bleibt unangetastet.';

-- --- fact_ausbuchung: gelöschte Deals ausschließen (Def. aus 029 + Filter) ---
-- Spaltenschnitt unverändert gegenüber 029 -> CREATE OR REPLACE zulässig.
CREATE OR REPLACE VIEW core.fact_ausbuchung AS
WITH b AS (
  SELECT
    id AS deal_id,
    payload,
    upper(regexp_replace(payload->>'title', '\s', '', 'g')) AS aktenzeichen
  FROM raw.pipedrive_deals d
  WHERE NOT EXISTS (
    SELECT 1 FROM raw.pipedrive_deal_deleted x WHERE x.id = d.id
  )
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
  (b.payload->'custom_fields'->>'215832fc2c61f065e6ad134c2a46485911fdcf28')::bigint AS anwalt_org_id
FROM b
WHERE b.aktenzeichen ~ '^\d{4}/\d+TG$';

-- --- fact_durchlauf: gelöschte Deals ausschließen (Def. aus 039 + Filter) ----
CREATE OR REPLACE VIEW core.fact_durchlauf AS
SELECT
  upper(regexp_replace(payload->>'title','\s','','g'))       AS aktenzeichen,
  id                                                          AS deal_id,
  (payload->>'add_time')::timestamptz                         AS add_time,
  (payload->>'won_time')::timestamptz                         AS won_time,
  (payload->>'stage_change_time')::timestamptz                AS stage_change_time,
  (payload->>'stage_id')::int                                 AS stage_id,
  payload->>'status'                                          AS status,
  CASE WHEN payload->>'won_time' IS NOT NULL
       THEN round(EXTRACT(EPOCH FROM ((payload->>'won_time')::timestamptz - (payload->>'add_time')::timestamptz))/86400.0, 1)
  END                                                         AS durchlaufzeit_tage
FROM raw.pipedrive_deals d
WHERE upper(regexp_replace(payload->>'title','\s','','g')) ~ '^\d{4}/\d+TG$'
  AND NOT EXISTS (
    SELECT 1 FROM raw.pipedrive_deal_deleted x WHERE x.id = d.id
  );

-- --- Beobachtbarkeit: welche Deals wurden als gelöscht ausgeschlossen? -------
CREATE OR REPLACE VIEW marts.v_deleted_deals AS
SELECT
  upper(regexp_replace(payload->>'title','\s','','g'))       AS aktenzeichen,
  (payload->>'value')::numeric(12,2)                          AS ehem_deal_value_brutto,
  payload->>'status'                                          AS ehem_status,
  extracted_at                                                AS geloescht_erkannt_am
FROM raw.pipedrive_deal_deleted
ORDER BY extracted_at DESC;
