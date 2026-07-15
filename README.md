# BI-Plattform Kfz-Sachverständigenbüro

Data Warehouse + BI-Layer für ein unabhängiges Kfz-Sachverständigenbüro.
Quellen (Pipedrive, sevDesk, autoiXpert) → ELT (TypeScript) → PostgreSQL
(`raw`/`core`/`marts`) → Metabase OSS. Betrieb auf bestehendem Coolify.

**Vor jeder Arbeit `CLAUDE.md` lesen** — dort stehen die nicht verhandelbaren
Domänenregeln (Brutto, `null ≠ 0`, Ausbuchung ≠ Kürzung, DSGVO …).

## Struktur

```
/docs        Architektur, ADRs, Feldmapping
/etl         TypeScript-Extraktoren (etl/pipedrive, etl/sevdesk, …)
/sql         Migrationen, nummeriert (001_raw.sql, 002_core.sql, …)
/fixtures    Golden Dataset (handgeprüfte Referenzdaten)
/scripts     Einmalige Hilfsskripte (Feldmapping, Generatoren)
CLAUDE.md    Verbindliche Domänen- und Repo-Regeln
```

## Setup (Entwicklung)

```bash
cp .env.example .env      # Werte eintragen (nie committen)
npm install
npm run typecheck
```

## Phasen

Der Aufbau folgt festen Phasen mit Abhängigkeiten (siehe `CLAUDE.md`):

| Phase | Inhalt | Status |
|---|---|---|
| 0 | Fundament: Repo, CLAUDE.md, Feldmapping | **in Arbeit** |
| 1 | Infrastruktur: Postgres + Metabase auf Coolify | offen |
| 2 | Pipedrive → `fact_ausbuchung` → Metabase | offen |
| 3 | sevDesk positionsscharf | offen |
| 4 | autoiXpert | offen |
| 5 | Kürzungsgrund automatisch (braucht Phase 3) | offen |
| 6 | Legacy-Backfill | offen |
| 7 | Dashboards & Betrieb | offen |

## Feldmapping (Phase 0)

Das autoritative Feldmapping wird aus der Pipedrive **Fields API v2** erzeugt:

```bash
npm run fetch:fields      # braucht PIPEDRIVE_API_TOKEN + PIPEDRIVE_COMPANY_DOMAIN
npm run generate:fields   # erzeugt etl/pipedrive/fields.generated.ts aus dem JSON
```

Bis der read-only Token vorliegt, ist `docs/field-mapping.json` provisorisch aus
Live-Stichproben abgeleitet (Status je Feld dokumentiert). Siehe
`docs/field-mapping.md`.
