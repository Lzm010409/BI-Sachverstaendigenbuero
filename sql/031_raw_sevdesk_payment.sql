-- 031_raw_sevdesk_payment.sql — Zahlungs-/Ausbuchungsbuchungen je sevDesk-Rechnung
--
-- Quelle: GET /Invoice/{id}/getCheckAccountTransactionLogs (embed checkAccount).
-- Grain: eine Buchung (CheckAccountTransactionLog) — d. h. ein auf die Rechnung
-- gebuchter Teilbetrag. Zwei Kontotypen sind relevant:
--   - „Geschäftskonto Postbank" (Konto 1100, type online) = tatsächlicher Zahlungs-
--     eingang (die evtl. gekürzte Regulierung des Versicherers).
--   - „Ausgebuchte Rechnungen" (Konto 1203, type offline) = Ausbuchung (Verlust).
-- Damit lässt sich der Zahlungsverlauf datiert rekonstruieren und die ECHTE Kürzung
-- als (Rechnungssumme − erste Zahlung) ableiten — statt aus OCR-Kürzungsschreiben.
--
-- DSGVO Option A: projectBooking() persistiert NUR Betrag, Datum, Konto (Name/Nr/Typ),
-- Rechnungs-/Transaktions-ID. payeePayerName (Geschädigter), IBAN, paymtPurpose,
-- primaNotaNo werden VOR dem Schreiben verworfen.

CREATE TABLE IF NOT EXISTS raw.sevdesk_invoice_bookings (
  id           bigint PRIMARY KEY,           -- CheckAccountTransactionLog-Objekt-ID
  invoice_id   bigint NOT NULL,              -- FK-artig auf sevdesk_invoices.id
  payload      jsonb  NOT NULL,              -- DSGVO-Whitelist (kein Personenbezug)
  extracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sevdesk_bookings_invoice
  ON raw.sevdesk_invoice_bookings (invoice_id);
