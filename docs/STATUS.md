# STATUS — Arbeitsstand & nächste Schritte

Handoff für den Session-Neustart (Container ist ephemer; alles Wichtige ist
committet). **Zuerst diese Datei + `CLAUDE.md` lesen.**

## Branches (wichtig!)

- **Designierter Arbeits-Branch:** `claude/sevdesk-phase-3-9a7g5k`.
- **Deploy-Branch:** `claude/repo-deployment-setup-emf5b8` — **die Coolify-App
  `bi-etl-warehouse` deployt von diesem Branch, nicht vom Arbeits-Branch.** Der
  Inhaber hat freigegeben, Phasen-Arbeit per Fast-Forward auch dorthin zu pushen.
  → **Nach jedem Commit auf beide Branches pushen:**
  `git push origin claude/sevdesk-phase-3-9a7g5k` **und**
  `git push origin claude/sevdesk-phase-3-9a7g5k:claude/repo-deployment-setup-emf5b8`.

## Erledigt (deployt & live verifiziert)

- **Phase 0–2** — Fundament, Infra, Pipedrive→`fact_ausbuchung`→marts. **1001 Deals** live.
- **Phase 3 — sevDesk positionsscharf.** `sql/005`–`008`,
  `etl/sevdesk/{client,project,extract-invoices,extract-positions,run-log,load-kategorien}.ts`.
  **Live: 994 Rechnungen, 6656 Positionen.** DSGVO Option A (kein Personenbezug in
  `raw`; `metabase_ro` auf `raw` gesperrt). Aktenzeichen-Join 99,95 %. Konsistenz
  988/994 exakt (6 Rabatt-Sonderrechnungen — geklärt, ignorieren).
- **Kategorien-Katalog = editierbare Seed-Tabelle** (`core.dim_positionskategorie_regel`,
  Migration `sql/008`). **Pflege: `fixtures/positionskategorie.json` editieren →
  redeploy.** `Sonstiges` 265 → 28.
- **ETL-Observability:** `marts.v_etl_run` (Erfolg/Fehler + rows je Quelle),
  `marts.v_etl_status` (Wasserstand). Erste Anlaufstelle bei Extraktionsproblemen.

## Betriebsfakten (für Verifikation & Deploy)

- **Coolify:** App `bi-etl-warehouse`, UUID `agsgcco44g4oko4swc0ocgc0`. Deploy:
  `GET {COOLIFY_BASE_URL}/api/v1/deploy?uuid=<uuid>` mit `Authorization: Bearer
  $COOLIFY_API_TOKEN`. `COOLIFY_BASE_URL` = `coolify.gollenstede.app` (Schema
  `https://` selbst voranstellen). Status: `/api/v1/deployments/<deployment_uuid>`.
- **`etl`-Deploy-Kette** (resilient): `migrate && { load-kategorien;
  extract-orgs; extract-deals; extract-invoices; extract-positions; }`.
  One-shot-Container, läuft nach „Deploy finished" **asynchron** durch (sevDesk-
  Positionen = ~1000 Calls, dauert Minuten). Fehler eines Schritts blockiert die
  anderen nicht mehr.
- **Warehouse-DB:** das mit Metabase gebündelte **Postgres 16**. **Kein direkter
  Zugriff aus der Session** (internes Coolify-Netz). Verifikation läuft über die
  **Metabase-API:** `metabase.gollenstede.app`, `POST /api/dataset`, Header
  `x-api-key: $METABASE_API_KEY`, Body `{"database":2,"type":"native","native":{"query":"…"}}`
  (läuft als `metabase_ro` → nur core/marts, kein `raw`).
- **Session-ENV vorhanden:** `COOLIFY_*`, `METABASE_API_KEY`, `PIPEDRIVE_*`,
  `SEVDESK_API_TOKEN`, `ETL_DB_PASSWORD`. **Egress zu sevDesk/autoiXpert ist per
  Netzwerk-Policy geblockt** → Fremd-APIs nur über vom Inhaber gelieferte
  curl-Ausgaben/Samples inspizieren (n8n-MCP bindet keine Credential an HTTP-Nodes).
- **Lokaler Test ohne Prod:** Wegwerf-Postgres 16 (`/usr/lib/postgresql/16/bin`),
  `npm run migrate` + `ALLOW_LOAD_GOLDEN=1 npm run load:sevdesk && npm run
  load:kategorien` + `npm run test:sevdesk`.

## Offener Betrieb (unverändert, Inhaber)

- **Nächtliche Aktualisierung:** n8n-Workflow „BI Warehouse — Nightly Refresh"
  (`mHZNeWIsEMSJIybF`, 02:00 UTC → Coolify-Deploy). **Status: INAKTIV** — am HTTP-
  Node Bearer-Credential „Coolify Deploy Token" anlegen, dann aktivieren.
- **Backup:** noch offen (`backup`-Service existiert, profile manual).

---

## NÄCHSTE SCHRITTE (Auswahl beim Neustart)

### Option A — Phase 4 (autoiXpert)  *(Unterbau gebaut & verifiziert; 1 Sample fehlt)*
Plan + Stand: **`docs/plan-phase-4.md`** (§ „Stand 2026-07-15"). Ziel: WBW, Restwert,
Wertminderung (+ Totalschaden/130-%) → Leitfragen 8 (BVSK-Korridor) & 10
(Totalschadenquote), **plus Bonus Leitfrage 2** (Versicherer je Fall aus
`insurance.organization_name`).

**Gebaut (typecheck grün, DSGVO-Filter gegen echtes Sample verifiziert, noch nicht
in der Deploy-Kette):** `sql/009_raw_autoixpert.sql`,
`etl/autoixpert/{client,project,extract-gutachten,run-log}.ts`, npm `extract:gutachten`.
- API bestätigt (Live-n8n): `GET https://app.autoixpert.de/externalApi/v1/reports/{id}`,
  **Bearer**. `token` = Aktenzeichen. `type` = Gutachtenart (liability→Haftpflicht).
- Extraktor ist **gegated**: ohne `AUTOIXPERT_API_TOKEN` No-op.

**Noch benötigt (nur noch das):**
1. **1 FERTIGES Gutachten als JSON** (`completion_date` gesetzt) — Fachwerte fehlen
   im aufgenommenen Zustand; nur so lassen sich die Feldnamen für WBW/Restwert/
   Wertminderung/Reparaturkosten/Nutzungsausfall bestätigen (`project.ts::fachwerte()`
   finalisieren). Frage: strukturierte Felder oder nur DAT-PDF?
2. `AUTOIXPERT_API_TOKEN` als Coolify-Secret (Bearer, read-only).
3. Fachfragen `plan-phase-4.md` §7.3–7.4 (Doppelquelle Reparaturkosten, Totalschaden-
   Definition).
Danach: `sql/010` (`fact_gutachten` + marts), Golden, Deploy-Kette ergänzen.

### Option B — Phase 5 (Kürzungsgrund / Durchsetzungsquote)  *(kein neuer Zugang nötig)*
Fundament steht (Phase 3 Positionen). Durchsetzungsquote = 1 − Σ Ausbuchung / Σ
Kürzung (Teilschuld/Haftungsquote raus). Braucht: Modellierung Kürzung je Position
vs. Ausbuchung; Plan `docs/plan-phase-5.md` erstellen (gegenlesen), dann bauen.

### Kleinaufgaben (jederzeit)
- Rest-`Sonstiges` (28) in `fixtures/positionskategorie.json` ergänzen, sobald der
  Inhaber die Namen zuordnet (Gestellung Werkstattausrüstung, Phantomkalkulation,
  „m. Bewertung", Tippfehler).
- n8n-Nightly aktivieren + Backup sauber lösen (s. o.).
