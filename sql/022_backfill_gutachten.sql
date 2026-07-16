-- 022_backfill_gutachten.sql — Phase 4: Gutachten-Fachwerte-Backfill (Validierungs-Scheibe)
--
-- Quelle: Gutachten-PDFs in OneDrive (…/Gutachten/JJJJ/MM/<Aktenzeichen>/…),
-- extrahiert via n8n-Reader (nativer OneDrive-Node → PDF-Text erste 3 Seiten →
-- Mistral-LLM), gelesen aus der Execution. Befund der Validierung:
--   * Auch die Archive (<2026, Fremdprogramm „Altova StyleVision") haben eine
--     TEXTEBENE und exakt das „Zusammenfassung des Gutachtens"-Format → KEIN OCR,
--     nur 3 Seiten, quasi kostenlos.
--   * Werte in sich stimmig (netto×1,19=brutto; Totalschaden erkannt, wenn
--     Reparaturkosten brutto > WBW).
--
-- DSGVO (wie sql/015): NUR numerische Fachwerte + Kurz-Klassifikation. Kein VIN,
-- kein Kennzeichen, kein Klarname, keine Freitexte/Kalkulationspositionen.
-- Aktenzeichen aus dem OneDrive-Ordnerpfad. Idempotenter Upsert je Aktenzeichen.
--
-- Dies ist die geprüfte 12er-Scheibe; der volle Lauf (~881 won-Fälle) folgt in
-- einer weiteren Migration. Recent Mai/Juni-2026 fehlen noch in OneDrive.

INSERT INTO raw.gutachten_fachwerte (aktenzeichen, payload, quelle_datei, extracted_at) VALUES
  ('0226/1829TG', '{"wiederbeschaffungswert":9725,"restwert":3920,"wertminderung":null,"reparaturkosten_netto":8114.67,"reparaturkosten_brutto":9656.46,"schadenhoehe_brutto":9656.46,"nutzungsausfall_tagessatz":35,"reparaturdauer_tage":4,"beurteilung":"Reparaturschaden"}'::jsonb, '0226_1829TG_Gutachten.pdf', now()),
  ('0226/1834TG', '{"wiederbeschaffungswert":4085,"restwert":750,"wertminderung":null,"reparaturkosten_netto":3455.40,"reparaturkosten_brutto":4111.93,"schadenhoehe_brutto":4111.93,"nutzungsausfall_tagessatz":79,"reparaturdauer_tage":3,"beurteilung":"Totalschaden"}'::jsonb, '0226_1834TG_Gutachten.pdf', now()),
  ('1125/1759TG', '{"wiederbeschaffungswert":1650,"restwert":210.08,"wertminderung":null,"reparaturkosten_netto":2273.39,"reparaturkosten_brutto":2705.33,"schadenhoehe_brutto":2505.33,"nutzungsausfall_tagessatz":43,"reparaturdauer_tage":14,"beurteilung":"Totalschaden"}'::jsonb, '1125_1759TG_Gutachten.pdf', now()),
  ('1225/1779TG', '{"wiederbeschaffungswert":null,"restwert":null,"wertminderung":500,"reparaturkosten_netto":null,"reparaturkosten_brutto":null,"schadenhoehe_brutto":null,"nutzungsausfall_tagessatz":null,"reparaturdauer_tage":null,"beurteilung":"Bewertung"}'::jsonb, '1225_1779TG_archiviertes_gutachten.pdf', now()),
  ('1025/1733TG', '{"wiederbeschaffungswert":37200,"restwert":6300,"wertminderung":null,"reparaturkosten_netto":98754.31,"reparaturkosten_brutto":117517.63,"schadenhoehe_brutto":117517.63,"nutzungsausfall_tagessatz":119,"reparaturdauer_tage":14,"beurteilung":"Totalschaden"}'::jsonb, '1025_1733TG_Gutachten.pdf', now()),
  ('1125/1756TG', '{"wiederbeschaffungswert":26300,"restwert":null,"wertminderung":150,"reparaturkosten_netto":3796.25,"reparaturkosten_brutto":4517.54,"schadenhoehe_brutto":4367.54,"nutzungsausfall_tagessatz":79,"reparaturdauer_tage":2,"beurteilung":"Reparaturschaden"}'::jsonb, '1125_1756TG_Gutachten.pdf', now()),
  ('1125/1753TG', '{"wiederbeschaffungswert":6725,"restwert":1400,"wertminderung":null,"reparaturkosten_netto":5014.81,"reparaturkosten_brutto":5967.62,"schadenhoehe_brutto":5967.62,"nutzungsausfall_tagessatz":23,"reparaturdauer_tage":5,"beurteilung":"Reparaturschaden"}'::jsonb, '1125_1753TG_archiviertes_gutachten.pdf', now()),
  ('0225/1506TG', '{"wiederbeschaffungswert":23750,"restwert":null,"wertminderung":200,"reparaturkosten_netto":9379.21,"reparaturkosten_brutto":11161.26,"schadenhoehe_brutto":11161.26,"nutzungsausfall_tagessatz":74,"reparaturdauer_tage":2,"beurteilung":"Reparaturschaden"}'::jsonb, '0225_1506TG_archiviertes_gutachten.pdf', now()),
  ('0825/1683TG', '{"wiederbeschaffungswert":3750,"restwert":null,"wertminderung":250,"reparaturkosten_netto":1679.56,"reparaturkosten_brutto":1998.68,"schadenhoehe_brutto":1998.68,"nutzungsausfall_tagessatz":22,"reparaturdauer_tage":2,"beurteilung":"Reparaturschaden"}'::jsonb, '0825_1683TG_Gutachten.pdf', now()),
  ('1223/1029TG', '{"wiederbeschaffungswert":2450,"restwert":672.27,"wertminderung":null,"reparaturkosten_netto":2760.39,"reparaturkosten_brutto":3284.86,"schadenhoehe_brutto":3284.86,"nutzungsausfall_tagessatz":24,"reparaturdauer_tage":14,"beurteilung":"Totalschaden"}'::jsonb, '1223_1029TG_archiviertes_gutachten.pdf', now()),
  ('1224/1434TG', '{"wiederbeschaffungswert":11550,"restwert":null,"wertminderung":null,"reparaturkosten_netto":4395.79,"reparaturkosten_brutto":5230.99,"schadenhoehe_brutto":5230.99,"nutzungsausfall_tagessatz":59,"reparaturdauer_tage":2,"beurteilung":"Reparaturschaden"}'::jsonb, '1224_1434TG_archiviertes_gutachten.pdf', now())
ON CONFLICT (aktenzeichen) DO UPDATE
  SET payload = EXCLUDED.payload, quelle_datei = EXCLUDED.quelle_datei, extracted_at = now();
