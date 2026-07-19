-- 042_geo_plz4.sql — feineres Einzugsgebiet (4-stellige PLZ) + Geo-Centroide
--
-- Vom Inhaber freigegebene Lockerung: statt nur 2-stelligem PLZ-Gebiet zusätzlich
-- die 4-STELLIGE PLZ (4 von 5 Ziffern → Gebiet, keine Adresse; nie 5-stellig).
-- Auswertungen aggregieren zusätzlich mit Mindestfallzahl.
--
-- Diese Migration: (1) raw um plz4 erweitern, (2) Personen-Geo-Wasserstand
-- zurücksetzen → nächster Deploy zieht die Personen VOLL neu (füllt plz4 nach),
-- (3) Referenz-Tabelle core.dim_plz_geo (Centroid je plz4) anlegen — befüllt vom
-- Loader `etl/pipedrive/load-plz-geo.ts` aus fixtures/plz4_geo.json (öffentliche
-- Geodaten WZB, kein Personenbezug).

-- (1) raw-Spalte (raw bleibt ansonsten unangetastet)
ALTER TABLE raw.pipedrive_person_geo ADD COLUMN IF NOT EXISTS plz4 text;

-- (2) Voll-Reextraktion der Personen-Geodaten erzwingen (plz4 nachfüllen).
--     Idempotent: der Upsert in extract-persons überschreibt nur, Rohbestand
--     bleibt konsistent. Nur DIESER Quell-Wasserstand wird genullt.
DELETE FROM raw._sync_state WHERE source = 'pipedrive_person_geo';

-- (3) Centroid-Referenz je 4-stelliger PLZ (Loader füllt / aktualisiert)
CREATE TABLE IF NOT EXISTS core.dim_plz_geo (
  plz4    text PRIMARY KEY,
  lat     double precision NOT NULL,
  lon     double precision NOT NULL,
  n_plz5  int
);
COMMENT ON TABLE core.dim_plz_geo IS
  'Referenz: Centroid (Lat/Lon) je 4-stelligem PLZ-Gebiet, Mittel der 5-stelligen PLZ. Quelle WZB plz_geocoord (public domain). Kein Personenbezug.';
