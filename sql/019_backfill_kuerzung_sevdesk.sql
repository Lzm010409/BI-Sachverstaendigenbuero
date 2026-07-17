-- 019_backfill_kuerzung_sevdesk.sql — Phase 5: historischer Kürzungs-Backfill (Daten)
--
-- Quelle: Versicherer-Schadenzahlungs-/Abrechnungsschreiben aus OneDrive
-- (Ordner .../Gutachten/JJJJ/MM/<Aktenzeichen>/…). Extraktion via n8n-Reader
-- (nativer OneDrive-Node → Mistral-OCR → Mistral-LLM), gelesen aus der Execution.
--
-- Nur die ROHDATEN (Upsert nach raw). Die Marts (echte Kürzung = fakturiert −
-- gezahlt_sv) stehen in sql/020 (v_kuerzung_sevdesk) + sql/021 (Durchsetzung/
-- Diagnose) — bewusst getrennt, damit ein View-Fehler das Laden nicht blockiert.
--
-- Domänenregel (Inhaber 2026-07-16): Kürzung wird NICHT aus dem Brief geraten,
-- sondern berechnet = fakturierte SV-Kosten (sevDesk/Deal) − gezahlte SV-Kosten
-- (Brief). Der Brief liefert nur `sachverstaendigenkosten` (= gezahlt) + Kontext.
-- Aktenzeichen aus dem OneDrive-Ordnerpfad (LLM verliest es oft). Beträge brutto.
--
-- DSGVO: nur PII-freie Fakten (Aktenzeichen, Versicherer = jur. Person,
-- Schadennummer = pseudonyme Referenz, Beträge, Datum). Keine Klarnamen/VIN/Kennzeichen.

INSERT INTO raw.kuerzungsschreiben (letter_key, aktenzeichen, payload, quelle, extracted_at) VALUES
  ('1025/1742TG|AD2025-41508200|onedrive', '1025/1742TG',
   '{"versicherer":"ADAC Autoversicherung AG","schadennummer":"AD2025-41508200","datum":"2025-11-21","sachverstaendigenkosten":361.60,"zahlungsbetrag":2195.87}'::jsonb,
   'onedrive-backfill', now()),
  ('0825/1686TG|AD2025-41285799|onedrive', '0825/1686TG',
   '{"versicherer":"ADAC Autoversicherung AG","schadennummer":"AD2025-41285799","datum":"2025-09-24","sachverstaendigenkosten":379.25,"zahlungsbetrag":3238.37}'::jsonb,
   'onedrive-backfill', now()),
  ('1224/1434TG|AS2024-51575584|onedrive', '1224/1434TG',
   '{"versicherer":"Allianz Versicherungs-AG","schadennummer":"AS2024-51575584","datum":"2025-02-14","sachverstaendigenkosten":1082.72,"zahlungsbetrag":1082.72}'::jsonb,
   'onedrive-backfill', now()),
  ('0225/1506TG|AS2025-50260354|onedrive', '0225/1506TG',
   '{"versicherer":"Allianz Versicherungs-AG","schadennummer":"AS2025-50260354","datum":"2025-03-06","sachverstaendigenkosten":1532.62,"zahlungsbetrag":6968.76}'::jsonb,
   'onedrive-backfill', now()),
  ('1223/1029TG|AS2023-71323092|onedrive', '1223/1029TG',
   '{"versicherer":"Allianz Versicherungs-Aktiengesellschaft","schadennummer":"AS2023-71323092","datum":"2023-12-14","sachverstaendigenkosten":572.08,"zahlungsbetrag":1637.35}'::jsonb,
   'onedrive-backfill', now()),
  ('0825/1683TG|AD2025-41184142|onedrive', '0825/1683TG',
   '{"versicherer":"ADAC Autoversicherung AG","schadennummer":"AD2025-41184142","datum":"2025-10-06","sachverstaendigenkosten":489.21,"zahlungsbetrag":2753.56}'::jsonb,
   'onedrive-backfill', now()),
  ('1122/694TG|22-11-531-612460|onedrive', '1122/694TG',
   '{"versicherer":"HUK-COBURG","schadennummer":"22-11-531/612460","datum":"2022-12-02","sachverstaendigenkosten":589.05,"zahlungsbetrag":589.05}'::jsonb,
   'onedrive-backfill', now())
ON CONFLICT (letter_key) DO UPDATE
  SET aktenzeichen = EXCLUDED.aktenzeichen, payload = EXCLUDED.payload,
      quelle = EXCLUDED.quelle, extracted_at = now();
