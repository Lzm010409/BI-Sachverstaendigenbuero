-- 046_gutachten_feed_log_view.sql — Diagnose-Sicht auf das Gutachten-Feed-Protokoll
--
-- Macht raw.gutachten_fetch_log für Metabase (metabase_ro, kein raw-Zugriff) lesbar.
-- Enthält u. a. die temporäre '#DIAG'-Zeile mit pdf-parse-Layout-Schnipseln um die
-- Geldlabels (nur Zahl/Label-Kontext, kein Personenbezug) zur exakten Parser-Justierung.
CREATE OR REPLACE VIEW marts.v_gutachten_feed_log AS
SELECT aktenzeichen, status, note, attempted_at
FROM raw.gutachten_fetch_log;
