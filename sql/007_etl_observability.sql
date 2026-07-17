-- 007_etl_observability.sql — ETL-Laufprotokoll, lesbar über Metabase (Phase 3)
--
-- Der `etl`-Container ist One-shot; seine Logs sind nach dem Lauf nicht ueber die
-- Coolify-API abrufbar. Dieses Protokoll macht Erfolg/Fehler je Extraktions-Quelle
-- ueber core/marts sichtbar (metabase_ro-lesbar). Fehlertexte stammen aus unseren
-- eigenen catch-Bloecken (err.message), nicht aus Rohdaten -> kein Personenbezug.

CREATE TABLE IF NOT EXISTS core._etl_run (
  id      bigserial PRIMARY KEY,
  source  text        NOT NULL,          -- z. B. 'sevdesk_invoices'
  status  text        NOT NULL,          -- 'ok' | 'error'
  rows    integer,                       -- verarbeitete Datensaetze (bei ok)
  error   text,                          -- gekuerzte Fehlermeldung (bei error)
  ran_at  timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON core._etl_run TO metabase_ro;

-- Letzte Laeufe je Quelle (7 Tage), fuer schnelle Diagnose.
CREATE OR REPLACE VIEW marts.v_etl_run AS
SELECT source, status, rows, error, ran_at
FROM core._etl_run
WHERE ran_at > now() - interval '7 days'
ORDER BY ran_at DESC;

-- Wasserstand je Quelle (aus raw._sync_state; die View laeuft mit etl-Rechten,
-- daher fuer metabase_ro lesbar, ohne raw freizugeben).
CREATE OR REPLACE VIEW marts.v_etl_status AS
SELECT source, last_updated_ts, last_run
FROM raw._sync_state;
