-- 017_raw_kuerzungsschreiben.sql — Kürzungsschreiben (Phase 5, echte Kürzung)
--
-- Quelle: Kürzungs-/Regulierungsschreiben der Versicherer, per Outlook-Anhang oder
-- aus den OneDrive-Fallordnern. Extraktion in n8n via Mistral-OCR + LLM (Schema),
-- DSGVO: nur Fakten/Zahlen (Aktenzeichen, Kürzungsbetrag, Versicherer, Schaden-
-- nummer, Datum, gezahlte SV-Kosten, Zahlungsbetrag) — KEIN Freitext, kein Klarname.
--
-- Das ist die ECHTE Kürzung (Versicherer-Behauptung), die der sevDesk-Differenz
-- fehlt (s. sql/014). Zusammen mit fact_forderungsverlust (Ausbuchung) ergibt sich
-- die belastbare Durchsetzungsquote.
--
-- `letter_key` (Dedup) = aktenzeichen|schadennummer|kuerzungsbetrag, in n8n gesetzt.

CREATE TABLE IF NOT EXISTS raw.kuerzungsschreiben (
  letter_key   text PRIMARY KEY,
  aktenzeichen text,
  payload      jsonb NOT NULL,      -- LLM-Extrakt (nur Zahlen/Fakten)
  quelle       text,                -- 'outlook' | 'onedrive' (+ Herkunft)
  extracted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_kuerzungsschreiben_aktenzeichen
  ON raw.kuerzungsschreiben (aktenzeichen);
