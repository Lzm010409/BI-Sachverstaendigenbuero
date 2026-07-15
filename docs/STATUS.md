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

## Deployment (erledigt, 2026-07-15)

ETL-Ressource `bi-etl-warehouse` in Coolify (`coolify.gollenstede.app`) läuft:

- **Ziel-DB:** das mit dem Metabase-Service (Env 28) gebündelte **Postgres 16**.
  Warehouse-DB `warehouse`, Host `postgresql`, erreichbar über das externe
  Docker-Netz des Metabase-Service (`WAREHOUSE_NETWORK` = Service-UUID).
- **Bootstrap** (Rollen `etl`/`metabase_ro` + DB `warehouse`) war bereits
  gelaufen; Metabase liest das Warehouse als `metabase_ro`.
- **Deploy-Service `etl`:** migrate (`sql/001`–`004`) → `extract:orgs` →
  `extract:deals`. Idempotent/inkrementell, läuft bei jedem Deploy.
- **Verifiziert** (via Metabase-API gegen die Live-DB): Migrationen angewandt,
  alle Views vorhanden, `raw`/`_meta` für `metabase_ro` gesperrt (DSGVO ok),
  **Golden 20/20 grün**.
- **Re-Baseline Golden:** 4 Deals (355/465/585/607) hatten inzwischen einen in
  Pipedrive nachgetragenen Ausbuchungsgrund (74 bzw. 69) — an der Quelle
  bestätigt, Fixture entsprechend aktualisiert. Kein Pipeline-Bug.
- **Golden ist kein Deploy-Gate** mehr (eigener `golden`-Service, profile
  `manual`), damit legitime Datenänderungen Deploy/Extraktion nicht blockieren.

Betrieb offen (manuell in Coolify einzurichten): Scheduled Tasks für
`docker compose run --rm etl` (nächtliche Aktualisierung), `... golden`
(Canary) und `... backup` (nächtliches pg_dump).

## NÄCHSTER SCHRITT

**Phase 3 (sevDesk positionsscharf)** planen. Voraussetzung für Phase 5
(Kürzungsgrund).
