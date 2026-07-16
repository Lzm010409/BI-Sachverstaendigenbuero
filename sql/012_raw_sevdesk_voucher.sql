-- 012_raw_sevdesk_voucher.sql — sevDesk-Belege (Voucher) für Phase 5
--
-- Für die Durchsetzungsquote braucht es die TATSÄCHLICHE Ausbuchung. Der Inhaber
-- erstellt je Ausbuchung einen sevDesk-Beleg (Voucher) mit dem Titel
-- „Forderungsverlust <Aktenzeichen>"; dessen Betrag ist der Ausbuchungsbetrag.
-- Diese Belege sind eine EIGENE, zuverlässige Ausbuchungsquelle (die Pipedrive-
-- `ausgebucht_betrag`-Erfassung ist dünn).
--
-- Wie 005: letzter Snapshot je Beleg (Upsert per id), timestamptz/UTC.
-- ABWEICHUNG „raw ist unverändert": `payload` ist DSGVO-GEFILTERT (Option A) — der
-- Voucher-`supplier`/`supplierName` (Kreditor, ggf. natürliche Person) und alle
-- Kontakt-/Adressfelder werden VOR dem Schreiben verworfen (etl/sevdesk/project.ts,
-- projectVoucher). `description` (Belegtitel inkl. Aktenzeichen) ist ein
-- Geschäftsschlüssel ohne Personenbezug und bleibt.

CREATE TABLE IF NOT EXISTS raw.sevdesk_vouchers (
  id           bigint PRIMARY KEY,           -- sevDesk Voucher-Objekt-ID
  aktenzeichen text,                          -- aus description extrahiert (normalisiert)
  payload      jsonb  NOT NULL,              -- DSGVO-gefiltertes Whitelist-Projekt
  extracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sevdesk_vouchers_aktenzeichen
  ON raw.sevdesk_vouchers (aktenzeichen);

-- Wasserstand nutzt raw._sync_state. Neue Quelle: 'sevdesk_vouchers'.
