# `scratchpad/` — Session-Helfer (Metabase-Queries & Dashboard-Builder)

Ad-hoc-Werkzeuge für Analyse und Metabase-Pflege. **Nicht Teil der Deploy-Kette** —
hier läuft nichts automatisch; die Skripte werden von Hand aufgerufen.

## Metabase-Zugriff

Das Warehouse-Postgres ist aus der Session nicht direkt erreichbar → alles läuft über
die **Metabase-API** (`https://metabase.gollenstede.app`, Warehouse = database id 2).

| Datei | Was |
|---|---|
| `mbq.py` | **Query-Helfer.** Führt native SQL gegen das Warehouse aus (`POST /api/dataset`, via `curl`, Key `METABASE_API_KEY`). Nutzung: `python3 mbq.py "SELECT …"` oder `python3 mbq.py - < datei.sql`. `metabase_ro` sieht nur `core`/`marts`. |

## Dashboard-Builder (idempotent)

Legen Cards/Dashboards über die Metabase-API an (`POST/PUT /api/card`, `/api/dashboard`).
Der schreibfähige Key ist derselbe `METABASE_API_KEY` (User `claude_gob_laptop_RW`).

| Datei | Baut |
|---|---|
| `build_dashboards.py` | die 5 Basis-Dashboards (Durchsetzung, Gutachten, Umsatz, Geo, Saisonalität). |
| `build_anwalt_dashboard.py` | Dashboard „Auftraggeber & Anwälte" (LF4). |
| `build_anwalt_kreuz.py` | Dashboard „Anwälte × Versicherer" (Schaden/Geo/Kürzung/Durchsetzung). |
| `update_durchsetzung_cards.py` | stellt die Durchsetzungs-Cards auf die belastbare Logik um. |
| `rebuild_kuerzung_cards.py` | stellt Kürzung/Durchsetzung-Cards auf die **zahlungsbasierten** Views um. |
| `kanon_test.sql` | Testquery für die Versicherer-Kanonisierung (`sql/035`). |

## Hinweise

- Die Builder sind idempotent (Sammlung/Dashboards per Name finden-oder-anlegen),
  können also gefahrlos erneut laufen.
- Card-Queries werden **erst gegen die Live-DB getestet** (mbq.py), dann angelegt.
- Sammlung in Metabase: „BI — Kfz-Sachverständigenbüro" (`/collection/5`).
