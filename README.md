# BI-Plattform Kfz-Sachverständigenbüro

Data Warehouse + BI-Layer für ein unabhängiges Kfz-Sachverständigenbüro.
Quellen (Pipedrive, sevDesk, autoiXpert/Gutachten-PDFs) → ELT (TypeScript) →
PostgreSQL (`raw`/`core`/`marts`) → Metabase OSS. Betrieb auf bestehendem Coolify.

**Vor jeder Arbeit `CLAUDE.md` lesen** — dort stehen die nicht verhandelbaren
Domänenregeln (brutto, `null ≠ 0`, Ausbuchung ≠ Kürzung ≠ Haftungsquote, DSGVO …).
**Aktueller Stand & Handoff: `docs/STATUS.md`.**

## Datenfluss

```
Pipedrive ─┐
sevDesk   ─┼─► etl/ (TypeScript, DSGVO-Whitelist) ─► raw ─► core (Views) ─► marts (Views) ─► Metabase
Gutachten ─┘        (Deploy-Kette im etl-Container)        fact_/dim_        v_*            Dashboards
n8n  ── ereignisgetrieben (Mail/OneDrive → OCR/Parser → raw) ──┘
```

## Struktur — jeder Teil hat eine eigene README

| Ordner | Inhalt | README |
|---|---|---|
| `sql/` | nummerierte, idempotente Migrationen (raw/core/marts) | `sql/README.md` |
| `etl/` | Extraktoren Quellen → `raw` (pipedrive, sevdesk, gutachten, autoixpert) | `etl/README.md` (+ je Unterordner) |
| `n8n/` | ereignisgetriebene Workflows (Kürzungsschreiben, Gutachten-Fachwerte) | `n8n/README.md` |
| `scripts/` | Migration, Feldmapping-Generator, lokale Tests, Betrieb | `scripts/README.md` |
| `fixtures/` | Golden Dataset + editierbare Seeds (Positionskategorie) | `fixtures/README.md` |
| `docker/` | Container-Image für Migrate/ETL | `docker/README.md` |
| `docs/` | Architektur, ADRs, Feldmapping, Pläne, **STATUS** | `docs/README.md` |
| `scratchpad/` | Metabase-Query-Helfer & Dashboard-Builder (Session-Tools) | `scratchpad/README.md` |
| `CLAUDE.md` | verbindliche Domänen- & Repo-Regeln | — |

## Setup (Entwicklung)

```bash
cp .env.example .env      # Werte eintragen (nie committen)
npm install
npm run typecheck
```

Lokale Verifikation ohne Prod (Wegwerf-Postgres + Golden Dataset): siehe
`scripts/README.md`.

## Phasenstand

| Phase | Inhalt | Status |
|---|---|---|
| 0–2 | Fundament, Infra, Pipedrive → `fact_ausbuchung` → Metabase | **live** (1001 Deals) |
| 3 | sevDesk positionsscharf | **live** (994 Rechnungen, 6656 Positionen) |
| 4 | Gutachten-Fachwerte (WBW/Restwert/… aus PDFs) | **live** (~591 Gutachten) |
| 5 | Kürzung/Durchsetzung — **zahlungsbasiert** aus sevDesk-Buchungen | **live** (183 Fälle); Grund aus Ausbuchungsgrund + Schreiben |
| 6 | Legacy-Backfill | teilweise |
| 7 | Dashboards & Betrieb | **live** (7 Metabase-Dashboards) |

Details und offene Punkte: `docs/STATUS.md`.

## Deploy

Coolify-App `bi-etl-warehouse` deployt vom Deploy-Branch. Beim **UI-Deploy** läuft
`scripts/migrate.ts` (Schema) + die Extraktoren-Kette. Danach Metabase-Views/
Dashboards aktuell. Siehe `docs/RUNBOOK.md` und `docker/README.md`.
