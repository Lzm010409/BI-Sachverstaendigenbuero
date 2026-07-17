-- 005_raw_sevdesk.sql — Rohtabellen für die sevDesk-Extraktion (Phase 3)
--
-- Wie bei Pipedrive: der letzte Snapshot je Entität genügt (Upsert per id),
-- Zeitstempel timestamptz/UTC.
--
-- ABWEICHUNG von „raw ist unverändert": das `payload` ist bereits DSGVO-GEFILTERT
-- (Option A — Personenbezug wird gar nicht erst persistiert). Das ist bewusst und
-- konsistent mit der bestehenden Pipedrive-Regel („Freitextfelder mit Personen-
-- bezug nicht übernehmen"). Die Filterung passiert VOR dem Schreiben im Extraktor
-- (etl/sevdesk/project.ts). sevDesk-Rechnungen enthalten den Rechnungsempfänger
-- (oft eine natürliche Person = der Geschädigte) sowie Adress-/Freitextfelder;
-- nichts davon landet hier. Persistiert wird nur, was für die Positions-/Kürzungs-
-- analyse (Phase 5) nötig ist: Positionen, Beträge, Steuersätze, Kategorie-Signale
-- (part/unity), Rechnungs-Objekt-ID, Rechnungsnummer und Datumsfelder.

CREATE TABLE IF NOT EXISTS raw.sevdesk_invoices (
  id           bigint PRIMARY KEY,           -- sevDesk Invoice-Objekt-ID (Join-Ziel)
  payload      jsonb  NOT NULL,              -- DSGVO-gefiltertes Whitelist-Projekt
  extracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS raw.sevdesk_invoice_positions (
  id           bigint PRIMARY KEY,           -- sevDesk InvoicePos-Objekt-ID
  invoice_id   bigint NOT NULL,              -- FK-artig auf sevdesk_invoices.id
  payload      jsonb  NOT NULL,              -- DSGVO-gefiltert (kein Freitext, kein contact)
  extracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sevdesk_positions_invoice
  ON raw.sevdesk_invoice_positions (invoice_id);

-- Wasserstand nutzt die bestehende raw._sync_state (aus 002_raw.sql).
-- Neue Quellen: 'sevdesk_invoices'. (Positionen werden je Rechnung nachgeladen,
-- daher kein eigener Wasserstand nötig.)
