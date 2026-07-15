# STATUS — Arbeitsstand & nächster Schritt

Kurznotiz für Session-Wechsel (der Container ist ephemer; alles Wichtige ist
committet). **Aktueller Arbeits-Branch: `claude/sevdesk-phase-3-9a7g5k`**
(auf den Stand von `repo-deployment-setup-emf5b8` fast-forwarded; Phase 3 baut
darauf auf).

## Erledigt (gepusht)

- **Phase 0** — Fundament: CLAUDE.md, Feldmapping, `fields.generated.ts`.
- **Phase 1** — Infra: Bootstrap-SQL, `sql/001_init.sql`, `scripts/migrate.ts`,
  `scripts/backup.sh`, `docker-compose.yml`, `docs/RUNBOOK.md`.
- **Phase 2** — Pipedrive→`fact_ausbuchung`→marts: `sql/002`–`004`, Pipedrive-
  Extraktoren, Golden-Set. **Deployt & live verifiziert** (s. u.).
- **Phase 3** — sevDesk positionsscharf: `sql/005_raw_sevdesk.sql`,
  `sql/006_core_sevdesk.sql`, `etl/sevdesk/{client,project,extract-invoices,extract-positions}.ts`,
  Fixture + `scripts/{load,test}-sevdesk.ts`, `etl`-Deploy-Service ergänzt.
  **Deployt & live verifiziert** (2026-07-15, s. u.). Zusätzlich `sql/007` +
  `etl/sevdesk/run-log.ts`: ETL-Observability (`marts.v_etl_run`/`v_etl_status`).

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

## Phase 3 (sevDesk positionsscharf) — gebaut & lokal verifiziert (2026-07-15)

**DSGVO Option A** umgesetzt: `etl/sevdesk/project.ts` reduziert Invoice/InvoicePos
vor dem Schreiben auf ein personenbezugsfreies Whitelist-Projekt (kein `contact`,
keine Adresse, kein Freitext `text`, kein eingebetteter Invoice-Block). Nur Beträge,
Steuersätze, Positions-/Kategorie-Signale (`part`/`unity`), Rechnungs-Objekt-ID,
Rechnungsnummer, Datumsfelder landen in `raw`.

**Struktur-Inspektion:** direkter sevDesk-Zugriff aus der Web-Session ist per
Netzwerk-Policy geblockt (my./api.sevdesk.de → CONNECT-403), und das n8n-MCP bindet
**keine** Credential an einen HTTP-Node (`sevDeskApi` **und** `httpHeaderAuth`
abgelehnt). Lösung: Inhaber hat eine echte Rechnung (Objekt-ID `129183018`, Az
`0726/2012TG`) inkl. 8 Positionen als JSON geliefert → Struktur daraus abgeleitet.

**Datenmodell:** `core.fact_rechnungsposition` (Grain: eine InvoicePos), Join zum
Aktenzeichen zweistufig (primär `fact_ausbuchung.sevdesk_rechnung_id` == Invoice-
Objekt-ID; Fallback: Aktenzeichen-Präfix aus `invoiceNumber`). `dim_positionskategorie`
datengetrieben (CASE-Mapping, neue Namen → `Sonstiges`). Marts:
`v_rechnungsposition_monat`, `v_position_je_kategorie`, `v_rechnung_konsistenz`.

**Lokal end-to-end verifiziert** (Wegwerf-Postgres 16): Migrationen 001–006 sauber,
`test:sevdesk` grün (DSGVO-Filter lässt keinen Personenbezug durch; 8 Positionen;
Kategorien korrekt; Aktenzeichen abgeleitet), **Konsistenz `differenz=0`** (Σ
Positionen brutto == Rechnung `sumGross` == 1480,19), DSGVO-Grants greifen
(`metabase_ro` auf `raw` verweigert, core/marts erlaubt).

**Bestätigt:** Σ Positionen (brutto) == Rechnung `sumGross`. **Offen (Inhaber):**
- Ob Rechnung `sumGross` == Pipedrive `deal_value_brutto` (harter Cross-System-
  Assert für Phase 5 — an dieser Rechnung nicht prüfbar, da Deal-Value nicht vorlag).
- Kategorien-Katalog: CASE-Mapping in `sql/006` gegenlesen/ergänzen (aktuell aus
  1 Rechnung abgeleitet; deckt SV-Honorar, Fahrtkosten, Lichtbilder, Porto/Telefon,
  Bewertungsabfrage, EDV, Schichtdickenmessung, Restwertermittlung).
- Annahme prüfen: `invoiceNumber`-Präfix == Aktenzeichen (Fallback-Join).

## Deployment Phase 3 (erledigt & verifiziert, 2026-07-15)

Deploy-Branch der Coolify-App `bi-etl-warehouse` = **`claude/repo-deployment-setup-emf5b8`**
(nicht der Phasen-Branch!). Phase 3 wurde per Freigabe des Inhabers dorthin
fast-forwarded (Commits `a895b10`, `abd14fe`). Deploy via
`GET {COOLIFY_BASE_URL}/api/v1/deploy?uuid=agsgcco44g4oko4swc0ocgc0`.

- **Live-Zahlen (Metabase-API, DB-ID 2):** 994 Rechnungen, 6656 Positionen.
  ETL-Protokoll `marts.v_etl_run`: `sevdesk_invoices` ok/994,
  `sevdesk_invoice_positions` ok/6656.
- **Aktenzeichen-Join 99,95 %:** nur 2 von 4279 Positionen ohne Aktenzeichen
  (zweistufiger Fallback über `invoiceNumber`-Präfix greift).
- **Konsistenz:** 988/994 Rechnungen rekonzilieren exakt (Σ Positionen == `sumGross`).
  Die **6 Ausreißer** (Σ Positionen == 2× Rechnungssumme) sind vom Inhaber geklärt:
  **Rabatt** (kein Bug, keine Haftungsquote), es waren **Sonderrechnungen, die nicht
  weiterverfolgt werden → ignorieren.** `v_rechnung_konsistenz` bleibt als Melder
  solcher Fälle (relevant für Phase 5).
- **Erste Deploy-Panne (behoben):** die alte `&&`-Extraktionskette brach beim ersten
  Deploy vor sevDesk ab (transienter Pipedrive-Schritt) → 0 Rechnungen, ohne Log-
  Sicht. Fix: Observability (`sql/007`) + resiliente `;`-Kette (Pipedrive blockiert
  sevDesk nicht mehr). Zweiter Deploy grün.

## Offen für den Inhaber (Phase 3)

- **Kategorien-Katalog** (`CASE` in `sql/006`): 265 von 6656 Positionen = `Sonstiges`.
  Wiederkehrende neue Namen: **Systemgebühr** (+„m. Bewertung"), **Digitalisierungs-
  pauschale**, **Sonderrecherche**, „Gestellung Werkstattausrüstung/Personal",
  „Phantomkalkulation" (+ Tippfehler-Varianten). Ansehen: `core.dim_positionskategorie`
  (Zeilen mit `kategorie='Sonstiges'`). Zuordnung/Bearbeitung: mit Inhaber abstimmen;
  optional editierbare Seed-Tabelle statt `CASE`.
- **`sumGross == deal_value`**: vom Inhaber bestätigt (gilt regulär). Die 6
  Ausreißer sind Rabatt-Sonderrechnungen und werden nicht weiterverfolgt.

## NÄCHSTER SCHRITT

- Kategorien-Katalog mit dem Inhaber finalisieren (neue Namen zuordnen; ggf. Seed-
  Tabelle) — offen, auf Zuruf. (Die 6 Rabatt-Sonderrechnungen sind erledigt: ignorieren.)
- Danach **Phase 4 (autoiXpert)** oder **Phase 5 (Kürzungsgrund/Durchsetzungsquote)**
  — Phase 5 hat mit Phase 3 jetzt ihr Positions-Fundament.
