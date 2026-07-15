-- 009_raw_autoixpert.sql — Rohtabelle für die autoiXpert-Extraktion (Phase 4)
--
-- Analog zu sevDesk (005): der letzte Snapshot je Gutachten genügt (Upsert per id),
-- Zeitstempel timestamptz/UTC.
--
-- ABWEICHUNG von „raw ist unverändert": das `payload` ist bereits DSGVO-GEFILTERT
-- (Option A — Personenbezug wird gar nicht erst persistiert). Das ist bei autoiXpert
-- besonders kritisch: die Rohantwort ist personenbezugs-SCHWER — Klarname des
-- Geschädigten, Anschrift, E-Mail/Telefon, **VIN**, **mehrere Kennzeichen** und
-- Freitexte (Unfallhergang, Schadenbeschreibung, Plausibilität). Nach CLAUDE.md
-- dürfen VIN, Kennzeichen, Klarnamen und Freitexte GAR NICHT ins Warehouse. Die
-- Filterung passiert VOR dem Schreiben im Extraktor (etl/autoixpert/project.ts):
-- nur analysenotwendige, personenbezugsfreie Fachwerte, Dimensionen (Gutachtenart,
-- Versicherer/Anwalt/Werkstatt als juristische Personen), pseudonyme IDs und
-- Datumsfelder passieren die Whitelist. Alles andere fällt weg.
--
-- `id` = autoiXpert-Report-ID (Format z. B. "807KwgxI7Xez" — alphanumerisch, daher
-- text statt bigint). `aktenzeichen` wird vom zugehörigen Pipedrive-Deal mitgegeben
-- (Join-Key MMJJ/NummerTG); autoiXpert liefert es zusätzlich als `token` — beides
-- wird persistiert und lässt sich kreuzvalidieren.

CREATE TABLE IF NOT EXISTS raw.autoixpert_gutachten (
  id           text PRIMARY KEY,             -- autoiXpert Report-ID (Join-Ziel)
  aktenzeichen text,                          -- vom Deal mitgegeben, normalisiert
  payload      jsonb  NOT NULL,              -- DSGVO-gefiltertes Whitelist-Projekt
  extracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_autoixpert_gutachten_aktenzeichen
  ON raw.autoixpert_gutachten (aktenzeichen);

-- Wasserstand nutzt die bestehende raw._sync_state (aus 002_raw.sql).
-- Neue Quelle: 'autoixpert_gutachten'.
