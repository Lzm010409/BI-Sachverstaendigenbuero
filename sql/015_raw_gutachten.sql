-- 015_raw_gutachten.sql — Fachwerte aus den Gutachten-PDFs (Phase 4, OneDrive-Route)
--
-- Quelle: die „Zusammenfassung des Gutachtens" (Seite 2) jedes autoiXpert-Gutachtens
-- in OneDrive (`…/Gutachten/JJJJ/MM/MMJJ_NummerTG/…Gutachten.pdf`). Extraktion per
-- etl/gutachten/parse-fachwerte.ts (Label-Anker, whitespace-tolerant).
--
-- ABWEICHUNG „raw ist unverändert": `payload` ist bereits DSGVO-GEFILTERT — der
-- Parser liefert AUSSCHLIESSLICH numerische Fachwerte + Klassifikation. KEIN VIN,
-- KEIN Kennzeichen, KEIN Klarname, keine Freitexte, keine Kalkulationspositionen.
--
-- Grain: ein Gutachten je Aktenzeichen (Upsert per Aktenzeichen).

CREATE TABLE IF NOT EXISTS raw.gutachten_fachwerte (
  aktenzeichen text PRIMARY KEY,             -- MMJJ/NummerTG (normalisiert)
  payload      jsonb NOT NULL,               -- Fachwerte-Objekt (nur Zahlen/Klasse)
  quelle_datei text,                          -- OneDrive-Pfad/Dateiname (Herkunft)
  extracted_at timestamptz NOT NULL DEFAULT now()
);

-- Wasserstand nutzt raw._sync_state. Neue Quelle: 'gutachten_fachwerte'.
