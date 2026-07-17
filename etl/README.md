# `etl/` — Extraktoren (Quellen → `raw`)

TypeScript-Extraktoren, die die Quellsysteme abrufen und **DSGVO-gefiltert** nach
`raw.*` schreiben. Aus `raw` bauen dann die SQL-Views in `core`/`marts` alles
Weitere (siehe `sql/README.md`). Kein dbt — bewusst schlank.

## Wann läuft das?

In der **Deploy-Kette** (`docker-compose.yml`, Service `etl`, One-shot-Container):

```
migrate && { load-kategorien; extract-orgs; extract-deals; extract-persons;
             extract-invoices; extract-positions; extract-vouchers; extract-payments; }
```

Erst `migrate` (Schema), dann die Extraktoren nacheinander. Fehler eines Schritts
blockt die anderen nicht (resiliente Kette). Läuft **nach** „Deploy finished"
asynchron durch (sevDesk-Schritte = ~1000 API-Calls, dauert Minuten).

## Einheitliches Muster je Quelle

| Datei | Rolle |
|---|---|
| `client.ts`   | minimaler REST-Client (Auth, Pagination, Backoff bei 429/5xx), nur GET |
| `project.ts`  | **DSGVO-Whitelist**: projiziert Rohobjekte auf personenbezugsfreie Felder, BEVOR sie in `raw` landen |
| `extract-*.ts`| holt eine Entität, ruft `project*()`, macht idempotenten Upsert nach `raw.*` |
| `run-log.ts`  | schreibt Erfolg/Fehler + Zeilenzahl nach `marts.v_etl_run` (Observability) |

`db.ts` (eine Ebene höher) liefert den Postgres-Pool aus den `ETL_DB_*`-Env-Variablen.

## Unterordner

- **`pipedrive/`** — Deals, Organisationen, Personen(Geo). Der zentrale Fall-Stamm.
- **`sevdesk/`** — Rechnungen, Positionen, Belege (Ausbuchung), **Zahlungsbuchungen**
  (Kürzung/Durchsetzung). Plus Positionskategorie-Seed-Loader.
- **`gutachten/`** — Parser für die Fachwerte (WBW/Restwert/…) aus Gutachten-PDF-Text
  (wird von n8n genutzt).
- **`autoixpert/`** — Gutachten-API-Anbindung (gebaut, noch nicht in der Deploy-Kette).

Jeder Unterordner hat eine eigene README mit den Details.

## Grundregeln (aus `CLAUDE.md`)

- **`raw` ist heilig** — nur Whitelist-Felder, kein Klarname/Kennzeichen/VIN/Freitext.
- Alle Beträge **brutto**, `null ≠ 0`.
- Feldzugriff bei Pipedrive **nur** über benannte Konstanten aus
  `pipedrive/fields.generated.ts` (nie rohe Hash-Keys im Code).
