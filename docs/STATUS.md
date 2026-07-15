# STATUS — Arbeitsstand & nächster Schritt

Kurznotiz für Session-Wechsel (der Container ist ephemer; alles Wichtige ist
committet auf Branch `claude/bi-plattform-kfz-hxmpig`).

## Erledigt (gepusht)

- **Phase 0** — Fundament: CLAUDE.md, Feldmapping (`docs/field-mapping*`,
  `docs/labels.md`), `etl/pipedrive/fields.generated.ts`.
- **Phase 1** — Infra: `scripts/db/00-bootstrap-roles.sql`, `sql/001_init.sql`,
  `scripts/migrate.ts`, `scripts/backup.sh`, `docker-compose.yml`,
  `docs/RUNBOOK.md`. Lokal gegen PostgreSQL 16 verifiziert.
- **Phase 2** — Pipedrive→fact_ausbuchung→marts: `sql/002_raw.sql`,
  `etl/pipedrive/{client,extract-deals,extract-organizations}.ts`,
  `sql/003_core.sql`, `sql/004_marts.sql`, Golden-Set + `scripts/test-golden.ts`.
  Golden 20/20 grün. Golden-Werte vom Inhaber gegengeprüft (ok).

## Offen / vereinbart

- Ausbuchungshistorie belastbar **ab 2024** (nichts davor → kein harter Filter nötig).
- Neuer Ausbuchungsgrund „Ablehnung durch Versicherung" — `dim_ausbuchungsgrund`
  ist datengetrieben, fängt ihn automatisch.
- Metabase-Frage + Metabase-API-Key: **später**.
- Durchsetzungsquote: Design steht (1 − Σ Ausbuchung / Σ Kürzung, je Versicherer/
  Grund; Teilschuld/Haftungsquote raus) — Umsetzung in **Phase 5**.

## NÄCHSTER SCHRITT (nach Session-Neustart)

**ETL-Ressource in Coolify anlegen (Weg A, via Coolify-API).** Voraussetzung:
diese ENV-Variablen müssen in der Session vorhanden sein (sonst Neustart):
`COOLIFY_BASE_URL`, `COOLIFY_API_TOKEN`, `PIPEDRIVE_API_TOKEN`,
`PIPEDRIVE_COMPANY_DOMAIN`.

Ablauf:
1. `printenv` prüfen — sind die vier Variablen da?
2. Coolify-API: Compose-Ressource aus diesem Repo/Branch anlegen, ins
   Postgres-Netz hängen, Secrets setzen (Warehouse-DB + Pipedrive), deployen.
   Dabei laufen Migrationen 001–004.
3. Extraktion anstoßen (`extract:orgs`, `extract:deals`), `test:golden` grün.
4. Danach: **Phase 3 (sevDesk positionsscharf)** planen.

Voraussetzung DB: Bootstrap-SQL (Rollen `etl`/`metabase_ro` + DB `warehouse`)
ist in Phase 1 gelaufen; falls unklar, `scripts/db/00-bootstrap-roles.sql`
idempotent erneut ausführen.
