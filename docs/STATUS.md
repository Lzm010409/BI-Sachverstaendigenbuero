# STATUS — Arbeitsstand & nächster Schritt

Kurznotiz für Session-Wechsel (der Container ist ephemer; alles Wichtige ist
committet). **Aktueller Arbeits-Branch: `claude/repo-deployment-setup-emf5b8`**
(der Inhaber hat zugestimmt, Phase 3 ebenfalls auf diesem Branch zu bauen).

## Erledigt (gepusht)

- **Phase 0** — Fundament: CLAUDE.md, Feldmapping, `fields.generated.ts`.
- **Phase 1** — Infra: Bootstrap-SQL, `sql/001_init.sql`, `scripts/migrate.ts`,
  `scripts/backup.sh`, `docker-compose.yml`, `docs/RUNBOOK.md`.
- **Phase 2** — Pipedrive→`fact_ausbuchung`→marts: `sql/002`–`004`, Pipedrive-
  Extraktoren, Golden-Set. **Deployt & live verifiziert** (s. u.).

## Deployment Phase 2 (erledigt & verifiziert, 2026-07-15)

ETL-Ressource **`bi-etl-warehouse`** in Coolify (`coolify.gollenstede.app`, API v4):

- **App-UUID:** `agsgcco44g4oko4swc0ocgc0`, Environment 28, Netz `coolify`.
  Deploy anstoßen: `GET {COOLIFY_BASE_URL}/api/v1/deploy?uuid=<app-uuid>` mit
  `Authorization: Bearer $COOLIFY_API_TOKEN`. (Deploy „finished" = `up -d`
  abgesetzt; der `etl`-Container ist One-shot und läuft danach asynchron durch.)
- **Ziel-DB:** das mit dem **Metabase-Service** gebündelte **Postgres 16**
  (Service-UUID `b4kwswkscsskcs0sgc8g4kwc`). Host `postgresql`, DB `warehouse`,
  erreichbar über externes Docker-Netz `WAREHOUSE_NETWORK=b4kwswkscsskcs0sgc8g4kwc`.
  **`PG_MAJOR=16`** (nicht 17).
- **Bootstrap** (`etl`/`metabase_ro` + DB `warehouse`) existiert bereits;
  `ETL_DB_PASSWORD` lag als Session-ENV vor. Alle Secrets sind an der App gesetzt.
- **Deploy-Service `etl`:** migrate (`001`–`004`) → `extract:orgs` →
  `extract:deals` (idempotent/inkrementell). `golden` + `backup` = profile
  `manual` (kein Deploy-Gate).
- **Live-Verifikation via Metabase-API** (`metabase.gollenstede.app`, Warehouse =
  **DB-ID 2** als `metabase_ro`; `METABASE_API_KEY` war Session-ENV): Migrationen
  angewandt, `raw`/`_meta` für `metabase_ro` gesperrt (DSGVO ok), **1001 Deals**
  in `fact_ausbuchung`, 269 Orgs, **Golden 20/20 grün**.
- **Golden re-baselined:** Deals 355/465/585/607 hatten inzwischen einen in
  Pipedrive nachgetragenen Ausbuchungsgrund (355=74 Ablehnung Versicherung,
  übrige=69 Grundhonorar) — an der Quelle bestätigt, Fixture aktualisiert. Kein Bug.

## Betrieb / Automatik

- **Nächtliche Aktualisierung = Weg B (gewählt):** n8n-Workflow
  **„BI Warehouse — Nightly Refresh"** (`n8n-coolify.gollenstede.app`,
  Workflow-ID `mHZNeWIsEMSJIybF`) — Schedule 02:00 UTC → HTTP-GET auf den
  Coolify-Deploy-Endpunkt. **Status: INAKTIV.** Zu tun (Inhaber): am HTTP-Node ein
  Bearer-Auth-Credential „Coolify Deploy Token" (Wert = Coolify-API-Token)
  anlegen, dann Workflow aktivieren.
- **Backup: noch offen** (Weg B deckt es nicht ab). `backup`-Service existiert
  (`docker compose run --rm backup`, braucht laufenden Container-Kontext). Später
  sauber lösen (z. B. eigener kleiner Baustein / n8n).
- Hinweis: Coolify Scheduled Tasks laufen per `docker exec` in einem **laufenden**
  Container — passt nicht zum One-shot-Design, daher Weg B statt Scheduled Task.

## Offen / vereinbart (Domäne)

- Ausbuchungshistorie belastbar **ab 2024**.
- `dim_ausbuchungsgrund` ist datengetrieben (fängt neue Gründe automatisch).
- Durchsetzungsquote (1 − Σ Ausbuchung / Σ Kürzung; Teilschuld/Haftungsquote
  raus) → **Phase 5** (braucht Phase 3).

## NÄCHSTER SCHRITT — Phase 3 (sevDesk positionsscharf) BAUEN

Plan liegt gegengelesen in **`docs/plan-phase-3.md`**. Fixe Entscheidungen:
**DSGVO Option A** (Personenbezug gar nicht persistieren), Bau auf aktuellem Branch.
Join steht: `fact_ausbuchung.sevdesk_rechnung_id` → sevDesk **Invoice-Objekt-ID**
(per Deeplink bestätigt, z. B. Deal 355 → Rechnung `64614720`).

**BLOCKER:** Um korrekt/DSGVO-sicher zu bauen, muss die echte sevDesk-Struktur
inspiziert werden. Dafür in der Session den **read-only `SEVDESK_API_TOKEN`**
bereitstellen (wird ohnehin als Coolify-Secret gebraucht). Alternativ eine
Beispiel-Rechnung inkl. Positionen als JSON (Namen geschwärzt).
- sevDesk-API: `https://my.sevdesk.de/api/v1`, Endpunkte `Invoice`, `InvoicePos`
  bzw. `Invoice/{id}/getPositions`; Auth `api_token`/Header; Pagination
  `limit`/`offset`.
- n8n hat ein „SevDesk"-Credential (`httpHeaderAuth`, ID `745fOXYVTHY5XVKf`),
  aber das n8n-MCP lässt es nicht an einen HTTP-Node binden → Inspektion via n8n
  hat nicht geklappt.

Ablauf danach: Token → 1–2 echte Rechnungen inspizieren → `sql/005_raw_sevdesk.sql`
(+ Option-A-Filter im Extraktor `etl/sevdesk/*`) → `sql/006_core_sevdesk.sql`
(`fact_rechnungsposition`, `dim_positionskategorie`, marts) → Golden erweitern →
`etl`-Deploy-Service um sevDesk-Extraktion ergänzen. Offen für den Inhaber:
Positionskategorien-Katalog; ob Rechnungssumme brutto == Pipedrive `deal_value`.
