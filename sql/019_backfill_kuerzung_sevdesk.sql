-- 019_backfill_kuerzung_sevdesk.sql — Phase 5: historischer Kürzungs-Backfill
--
-- Quelle: Versicherer-Schadenzahlungs-/Abrechnungsschreiben aus OneDrive
-- (Ordner .../Gutachten/JJJJ/MM/<Aktenzeichen>/…). Extraktion via n8n-Reader
-- (nativer OneDrive-Node → Mistral-OCR → Mistral-LLM), gelesen aus der Execution.
--
-- Domänenregel (Inhaber-Entscheidung 2026-07-16): die ECHTE Kürzung wird NICHT
-- aus dem Brief geraten, sondern berechnet:
--     Kürzung = fakturierte SV-Kosten (sevDesk/Deal, verlässlich)
--               − gezahlte SV-Kosten (aus dem Brief).
-- Der Brief liefert also nur `sachverstaendigenkosten` (= gezahlt) + Kontext.
-- Alle Beträge brutto. Aktenzeichen kommt aus dem OneDrive-Ordnerpfad (der
-- LLM verliest es häufig), nicht aus der LLM-Ausgabe.
--
-- DSGVO: nur PII-freie Fakten (Aktenzeichen, Versicherer = jur. Person,
-- Schadennummer = pseudonyme Referenz, Beträge, Datum). Keine Klarnamen/VIN/Kennzeichen.

-- --- raw: die 7 gefundenen Schreiben (idempotenter Upsert) ---------------------
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

-- --- marts: echte Kürzung = fakturiert − gezahlt_sv ---------------------------
-- Ein Schreiben je Fall. Fakturierte SV-Kosten aus fact_ausbuchung
-- (deal_value_brutto = Rechnungssumme brutto, deckungsgleich mit den sevDesk-
-- Positionen). `plausibel` = Fall in sevDesk vorhanden UND gezahlt ≤ fakturiert
-- (fängt Fehl-Lesungen des Briefs ab, z. B. gezahlt > fakturiert).
CREATE OR REPLACE VIEW marts.v_kuerzung_sevdesk AS
WITH brief AS (
  SELECT aktenzeichen,
         max(versicherer)       AS versicherer,
         max(sv_kosten_gezahlt) AS gezahlt_sv,
         max(datum)             AS brief_datum
  FROM core.fact_kuerzungsereignis
  WHERE sv_kosten_gezahlt IS NOT NULL
  GROUP BY aktenzeichen
),
fakt AS (
  SELECT aktenzeichen, max(deal_value_brutto) AS fakturiert
  FROM core.fact_ausbuchung
  GROUP BY aktenzeichen
)
SELECT
  b.aktenzeichen,
  b.versicherer,
  f.fakturiert,
  b.gezahlt_sv,
  round(f.fakturiert - b.gezahlt_sv, 2)                          AS kuerzung_berechnet,
  b.brief_datum,
  (f.fakturiert IS NOT NULL AND b.gezahlt_sv <= f.fakturiert)    AS plausibel
FROM brief b
LEFT JOIN fakt f USING (aktenzeichen);

-- Echte Durchsetzungsquote je Fall: berechnete Kürzung vs. tatsächlich
-- ausgebuchter Forderungsverlust. Nur plausible Fälle.
CREATE OR REPLACE VIEW marts.v_durchsetzung_sevdesk AS
WITH fv AS (
  SELECT aktenzeichen, sum(forderungsverlust_brutto) AS ausgebucht
  FROM core.fact_forderungsverlust
  WHERE aktenzeichen IS NOT NULL
  GROUP BY aktenzeichen
)
SELECT
  k.aktenzeichen,
  k.versicherer,
  k.fakturiert,
  k.gezahlt_sv,
  k.kuerzung_berechnet,
  COALESCE(fv.ausbuchung, 0)                                             AS ausgebucht,
  k.kuerzung_berechnet - COALESCE(fv.ausbuchung, 0)                      AS durchgesetzt,
  CASE WHEN k.kuerzung_berechnet > 0
       THEN round(1 - COALESCE(fv.ausbuchung, 0) / k.kuerzung_berechnet, 4)
  END                                                                    AS durchsetzungsquote
FROM marts.v_kuerzung_sevdesk k
LEFT JOIN fv USING (aktenzeichen)
WHERE k.plausibel AND k.kuerzung_berechnet > 0;

-- Diagnose: ALLE Schreiben inkl. unplausibler (gezahlt>fakturiert, fehlende
-- sevDesk-Zuordnung) — erste Anlaufstelle, um Fehl-Lesungen nachzubessern.
CREATE OR REPLACE VIEW marts.v_kuerzung_sevdesk_diagnose AS
SELECT
  k.*,
  CASE
    WHEN k.fakturiert IS NULL              THEN 'kein sevDesk-Fall (z. B. vor SEVDESK_SINCE)'
    WHEN k.gezahlt_sv > k.fakturiert       THEN 'gezahlt > fakturiert — Brief vermutlich falsch gelesen'
    WHEN k.kuerzung_berechnet = 0          THEN 'voll gezahlt, keine Kürzung'
    ELSE 'ok'
  END AS befund
FROM marts.v_kuerzung_sevdesk k;
