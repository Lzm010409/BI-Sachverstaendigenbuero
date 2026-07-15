-- 002_raw.sql — Rohtabellen für die Pipedrive-Extraktion (Phase 2)
--
-- `raw` ist heilig: unveränderte JSONB-Antworten, nie transformiert. Der letzte
-- Snapshot je Entität genügt (Upsert per id). Zeitstempel sind timestamptz/UTC.

CREATE TABLE IF NOT EXISTS raw.pipedrive_deals (
  id           bigint PRIMARY KEY,
  payload      jsonb  NOT NULL,
  extracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS raw.pipedrive_organizations (
  id           bigint PRIMARY KEY,
  payload      jsonb  NOT NULL,
  extracted_at timestamptz NOT NULL DEFAULT now()
);

-- Wasserstand der inkrementellen Extraktion.
CREATE TABLE IF NOT EXISTS raw._sync_state (
  source          text PRIMARY KEY,          -- z. B. 'pipedrive_deals'
  last_updated_ts timestamptz,               -- höchstes update_time des letzten Laufs
  last_run        timestamptz
);
