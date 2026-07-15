# STATUS — Arbeitsstand & nächster Schritt

Kurznotiz für Session-Wechsel (der Container ist ephemer). Deployment-Arbeit
liegt auf Branch **`claude/repo-deployment-setup-g24l0l`** (Default-Branch des
Repos ist `claude/bi-plattform-kfz-hxmpig`; Inhalt identisch bis auf die
Deploy-Commits). **Auf `claude/repo-deployment-setup-g24l0l` weiterarbeiten.**

## Erledigt (gepusht)

- **Phase 0** — Fundament: CLAUDE.md, Feldmapping, `fields.generated.ts`.
- **Phase 1** — Infra: Bootstrap-SQL, `sql/001_init.sql`, `migrate.ts`,
  `backup.sh`, `docker-compose.yml`, RUNBOOK. Lokal gegen PG16 verifiziert.
- **Phase 2** — Pipedrive→fact_ausbuchung→marts: `sql/002_raw.sql`,
  `etl/pipedrive/*`, `sql/003_core.sql`, `sql/004_marts.sql`, Golden-Set +
  `test-golden.ts`. Golden 20/20 grün, vom Inhaber gegengeprüft.
- **Deployment vorbereitet** (Commits `f2c18ed`, `fce1b39`):
  - `docker-compose.yml`: neuer one-shot **`etl`**-Service läuft beim Coolify-
    Deploy die Kette **Migrationen → Extraktion (orgs+deals) → Golden** ab.
    `migrate`/`backup` liegen hinter Compose-Profile `tools` (nur manuell).
    Alle Services hängen am externen Netz `warehouse` (Name aus
    `WAREHOUSE_NETWORK`).
  - `docker/migrate.Dockerfile`: `COPY fixtures ./fixtures` (Golden braucht sie).

## Coolify — Ist-Zustand (via API erkundet, 2026-07-15)

- **Coolify:** `https://coolify.gollenstede.app`, API v4.0.0-beta.462.
  Token in ENV `COOLIFY_API_TOKEN`. Server `localhost`
  uuid `e4s0gog0ow0cgggk004c0ok8`.
- ⚠️ **Cloudflare blockt `Python-urllib` (Fehler 1010).** API-Calls mit **`curl`**
  machen, nicht mit Python `urllib`.
- **Postgres + Metabase** = ein Coolify-**Service** (nicht als „database"-Resource
  sichtbar!) im Projekt **metabase** (uuid `ik4w0koswggsw4k4gswkkssw`,
  Env production uuid `g8808os4scogs8s8ssc8c4ow`):
  - Service-uuid `b4kwswkscsskcs0sgc8g4kwc`, Status `running:healthy`.
  - Netz: **`b4kwswkscsskcs0sgc8g4kwc`** (extern). Postgres-Container:
    **`postgresql-b4kwswkscsskcs0sgc8g4kwc`**, PG **16**, DB `warehouse`, Rolle `etl`.
  - `postgres-init` hat Rollen `etl`/`metabase_ro` + DB `warehouse` **bereits
    angelegt** (Phase-1-Bootstrap erledigt). `etl` ist Owner von `warehouse`.
  - Metabase unter `https://metabase.gollenstede.app`.
- **ETL-Ressource angelegt:** App **`bi-etl-warehouse`**,
  uuid **`agsgcco44g4oko4swc0ocgc0`**, im Projekt metabase/production.
  Build-Pack `dockercompose`, public Repo `Lzm010409/BI-Sachverstaendigenbuero`,
  Branch `claude/repo-deployment-setup-g24l0l`, Compose `/docker-compose.yml`.
- **Env an der ETL-Ressource gesetzt (8/9):**
  `WAREHOUSE_DB_HOST=postgresql-b4kwswkscsskcs0sgc8g4kwc`, `WAREHOUSE_DB_PORT=5432`,
  `WAREHOUSE_DB_NAME=warehouse`, `ETL_DB_USER=etl`,
  `WAREHOUSE_NETWORK=b4kwswkscsskcs0sgc8g4kwc`, `PG_MAJOR=16`,
  `PIPEDRIVE_COMPANY_DOMAIN`, `PIPEDRIVE_API_TOKEN`.

## NÄCHSTER SCHRITT — nur noch Passwort + Deploy

**Blocker:** Es fehlt **`ETL_DB_PASSWORD`** (Passwort der DB-Rolle `etl`). Es ist
über die Coolify-API **nicht lesbar**. Quelle: Coolify → Service **metabase** →
Environment → `ETL_DB_PASSWORD`. Muss identisch zum dortigen Wert sein, sonst
scheitert die etl-Anmeldung. Der Inhaber liefert den Wert in dieser Session
(entweder als ENV `ETL_DB_PASSWORD` gesetzt, oder im Chat eingefügt).

Ablauf (alle API-Calls mit `curl`, `APP=agsgcco44g4oko4swc0ocgc0`,
`BASE=https://coolify.gollenstede.app`, Header
`Authorization: Bearer $COOLIFY_API_TOKEN`):

1. **`ETL_DB_PASSWORD` als Env setzen** (Wert via stdin, nicht loggen):
   ```
   KEY=ETL_DB_PASSWORD python3 -c 'import os,json;print(json.dumps({"key":"ETL_DB_PASSWORD","value":os.environ["ETL_DB_PASSWORD"],"is_preview":False}))' \
     | curl -sS -H "Authorization: Bearer $COOLIFY_API_TOKEN" -H "Content-Type: application/json" \
       -X POST --data @- "$BASE/api/v1/applications/$APP/envs"
   ```
   (Env-Update statt -create: HTTP `PATCH` auf `.../envs` mit demselben Body,
   falls der Key schon existiert.)
2. **Deploy anstoßen:**
   ```
   curl -sS -H "Authorization: Bearer $COOLIFY_API_TOKEN" \
     "$BASE/api/v1/deploy?uuid=$APP&force=false"
   ```
   Liefert `deployment_uuid`. Fortschritt/Logs:
   `GET $BASE/api/v1/deployments/{deployment_uuid}`.
3. **Verifizieren** (Container-Log des `etl`-Service): Reihenfolge im Log
   `== Migrationen ==` (001–004 angewandt) → `== Extraktion … ==` (orgs, deals)
   → `== Golden-Test ==` mit **`✓ Golden-Test grün: 20/20`**. Der `etl`-Container
   endet danach (exited 0) — in Coolify normal, kein Dauerdienst.
   - Falls Deploy-Log knapp ist: Coolify zeigt Container-Logs über die App-UI,
     oder erneut deployen und `deployments/{uuid}` pollen.
4. **DSGVO-Negativtest** (RUNBOOK Schritt 6, `metabase_ro` darf `raw` nicht lesen)
   und **Metabase-Datenquelle** (`warehouse` via `metabase_ro`) — danach.
5. **Phase 3 (sevDesk positionsscharf)** planen.

### Hinweise / Fallstricke
- `docker_compose_location` muss `/docker-compose.yml` sein (Coolify legte
  initial `.yaml` an — bereits auf `.yml` korrigiert).
- Extraktion nutzt read-only Pipedrive-Token → schreibt nur ins Warehouse `raw`.
  Redeploy wiederholt die Kette inkrementell (unschädlich).
- Kommt `getaddrinfo … postgresql-…` im Log: ETL-Container hängt nicht im Netz
  `b4kwswkscsskcs0sgc8g4kwc` → `WAREHOUSE_NETWORK` prüfen, Netz muss existieren.

## Offen / vereinbart
- Ausbuchungshistorie belastbar **ab 2024**.
- Ausbuchungsgrund „Ablehnung durch Versicherung" — `dim_ausbuchungsgrund` ist
  datengetrieben, fängt ihn automatisch.
- Durchsetzungsquote (1 − Σ Ausbuchung / Σ Kürzung, je Versicherer/Grund;
  Teilschuld/Haftungsquote raus) — Umsetzung in **Phase 5**.
