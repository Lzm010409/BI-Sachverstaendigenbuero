-- 026_raw_person_geo.sql — DSGVO-gefilterte Personen-Geodaten (Einzugsgebiet, LF7)
--
-- Quelle: Pipedrive-Personen (Geschädigte), extrahiert via
-- etl/pipedrive/extract-persons.ts. ABWEICHUNG „raw ist unverändert": es wird
-- NUR die PII-arme Geo-Information gespeichert — KEIN Name, KEINE Straße, KEIN
-- Kontakt. `plz_gebiet` = erste 2 Ziffern der Wohn-PLZ (nie 5-stellig), `ort` =
-- Wohnort (Stadt). Der Fallbezug läuft über deal.person_id (pseudonymer Schlüssel).
--
-- Grain: eine Person je person_id (Upsert). Wasserstand: raw._sync_state,
-- source='pipedrive_person_geo'.

CREATE TABLE IF NOT EXISTS raw.pipedrive_person_geo (
  person_id    bigint PRIMARY KEY,
  plz_gebiet   text,                       -- erste 2 Ziffern der PLZ (PLZ-Gebiet)
  ort          text,                        -- Wohnort (Stadt)
  extracted_at timestamptz NOT NULL DEFAULT now()
);
