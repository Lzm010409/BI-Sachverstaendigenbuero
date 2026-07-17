# `sql/` — Datenbank-Migrationen

Nummerierte, **idempotente** SQL-Migrationen, die das Warehouse-Schema aufbauen.
Sie laufen beim Deploy über `scripts/migrate.ts` (Service `etl` in
`docker-compose.yml`, Schritt `migrate`).

## Wie der Runner arbeitet (wichtig!)

- `scripts/migrate.ts` führt alle `sql/*.sql` **in numerischer Reihenfolge** aus und
  merkt sich jede Datei mit **SHA-256-Checksum** in der Tabelle `_meta._migrations`.
- **Eine bereits angewandte Datei darf NICHT mehr geändert werden** — weicht die
  Checksum ab, bricht der Deploy bewusst ab („Semantik nicht still verschieben").
  → **Korrekturen immer als NEUE, höher nummerierte Datei.** (Deshalb gibt es z. B.
  `030` als Korrektur zu `029` und `034`/`035` als Nachbesserungen.)
- Views werden mit `CREATE OR REPLACE VIEW` angelegt → beim nächsten Deploy neu
  gebaut. Spalten dürfen nur **am Ende ergänzt** werden (sonst `DROP VIEW` nötig).

## Schema-Konvention (drei Ebenen)

| Schema | Zweck | Regel |
|---|---|---|
| `raw`   | Rohantworten der Quellen, JSONB, DSGVO-gefiltert (Whitelist) | **heilig** — nie transformieren/löschen |
| `core`  | normalisierte Fakten/Dimensionen als **Views** (`fact_*`, `dim_*`) | reproduzierbar aus `raw`, kein Transform-Schritt |
| `marts` | Views für Metabase (`v_*`) | nur hierauf zeigen die Dashboards |

`metabase_ro` (Query-Rolle) sieht **nur `core` + `marts`**, nie `raw` (DSGVO).

## Landkarte der Migrationen

- `001`–`004` Fundament: Schemas, `raw.pipedrive_*`, `core.fact_ausbuchung`/`dim_*`, erste marts.
- `005`–`008` sevDesk: Rechnungen/Positionen, ETL-Observability, Positionskategorie-Seed.
- `009`–`014` Phase 5 Kürzung/Ausbuchung (Modell-Iterationen; `014` = Korrektur „Ausbuchung aus Forderungsverlust-Belegen").
- `015`–`016`, `022`–`023`, `025` Gutachten-Fachwerte (`raw.gutachten_fachwerte` → `core.fact_gutachten`, LF8/10) + Backfills.
- `017`–`021`, `024` Kürzungsschreiben (OCR) → `fact_kuerzungsereignis`, Durchsetzungs-Views.
- `026`–`027` Geo/Einzugsgebiet (LF7).
- `028` Durchsetzungsquote „belastbar" (nur `won`, NULL statt Schein-100 %).
- `029`–`030` Rechtsanwalt/Kanzlei als Dimension (`dim_anwalt`, LF4).
- `031`–`034` **zahlungsbasierte Kürzung/Durchsetzung** aus sevDesk-Buchungen
  (`fact_zahlung`, `v_durchsetzung_zahlung`; `034` = Perf-Fix).
- `035` Versicherer-Namen kanonisieren (`dim_versicherer_kanon`).

Details zu Domänenregeln (brutto, `null ≠ 0`, Kürzung ≠ Ausbuchung ≠ Haftungsquote)
stehen in `CLAUDE.md` und als Kommentar im Kopf jeder Migration.
