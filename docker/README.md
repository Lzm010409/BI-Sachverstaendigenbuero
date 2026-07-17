# `docker/` — Container-Images

## `migrate.Dockerfile`

Schlankes `node:20-alpine`-Image für den **`etl`-Service** (Migrations-Runner + ETL-
Jobs) aus `docker-compose.yml`. Baut so:

1. `package.json` + `package-lock.json` kopieren, `npm ci --omit=dev` (Layer-Caching).
2. `tsconfig.json`, `sql/`, `scripts/`, `etl/`, `fixtures/` kopieren.
3. `CMD` = `npx tsx scripts/migrate.ts` — im Compose durch die volle Deploy-Kette
   überschrieben (`migrate && { extractoren… }`).

Exit 0 bei Erfolg, sonst ≠ 0 → der Deploy schlägt fehl (gewollt).

## Zusammenspiel

`docker-compose.yml` (Repo-Root) orchestriert die Services (u. a. `etl` als
One-shot). Deployt wird über **Coolify** (App `bi-etl-warehouse`, UUID
`agsgcco44g4oko4swc0ocgc0`) vom Deploy-Branch. Wichtig: Die Migrationskette läuft
zuverlässig nur beim **UI-Deploy** („Removing old containers → New container
started"), nicht bei reinen API-Deploys. Build-Args/Secrets kommen aus der Coolify-
Env (`WAREHOUSE_DB_*`, `PIPEDRIVE_*`, `SEVDESK_*`, …).
