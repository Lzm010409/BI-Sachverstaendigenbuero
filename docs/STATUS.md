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

## AKTUELLER STAND (2026-07-15)

- **Phase 4 (Fachwerte): OneDrive-Route, im Bau.** Entscheidung: Fachwerte kommen aus
  den **Gutachten-PDFs in OneDrive** (M365/Graph bewiesen — `read_resource` liefert
  vollen Text, „Zusammenfassung" trägt alle Fachwerte). Gebaut & verifiziert:
  `etl/gutachten/parse-fachwerte.ts` (Label-Parser, an echtem Gutachten 10/10 Werte
  korrekt), `sql/015` `raw.gutachten_fachwerte` + `sql/016` `core.fact_gutachten` +
  `v_honorar_vs_schaden` (LF8) + `v_totalschaden_quote` (LF10) — lokal verifiziert
  (Reparatur- vs. Totalschaden-Klassifikation korrekt). **Offen:** n8n-Workflow
  (OneDrive → Parser → `raw.gutachten_fachwerte`) + Backfill. Alte autoiXpert-API-
  Route (`docs/status-phase-4.md`) nur noch für Versicherer-Zuordnung (LF2) relevant.
- **Phase 5 (Kürzung + Durchsetzungsquote): GEBAUT & verifiziert.** Plan:
  **`docs/plan-phase-5.md`** (gegenlesen). Zwei Inhaber-Entscheidungen umgesetzt:
  - **Kürzung** = sevDesk-Rechnungsdifferenz (`sumGross − paidAmount`), außer ±5 ct =
    MwSt (USt-Einbehalt). `sql/010` `core.fact_kuerzung` + marts (LF2). Nur `won`,
    Teilschuld/Haftungsquote getrennt, null≠0.
  - **Ausbuchung** = sevDesk-Beleg „Forderungsverlust <Aktenzeichen>" (eigene, voll-
    ständige Quelle). `sql/012` raw + `etl/sevdesk/extract-vouchers.ts` (DSGVO:
    supplier verworfen) + `sql/013` `core.fact_forderungsverlust`.
  **DEPLOYT & an Prod-Daten geprüft (2026-07-16, Deploy-Branch + Coolify).**
  **Kritischer Befund:** `sumGross − paidAmount` misst die Kürzung NICHT — sevDesk
  bucht die Rechnung bei Abschluss voll (Zahlung + Ausbuchungsbuchung), offener
  Betrag ~0 trotz realer Abschreibung (506/515 „Kürzungen" waren < 0,10 €). Korrektur
  `sql/014`: **Ausbuchung aus den Forderungsverlust-Belegen** (`fact_forderungsverlust`,
  89 Fälle / 34 k€) ist die zuverlässige Hauptlieferung → `v_forderungsverlust_je_versicherer`
  / `v_forderungsverlust_monat` (Leitfrage 5). Kürzungs-Views mit Bagatellgrenze entschärft.
  **Die echte Kürzung braucht das Kürzungsschreiben** → Strategie in
  `docs/strategie-kuerzung-und-pdf.md`.

## n8n-Workflows (Phase 4 & 5) — via HTTP-Ingest (n8n ≠ Warehouse-Netz)

n8n erreicht die DB nicht → Schreiben/Lesen über den **HTTP-Ingest-Dienst**
`etl/ingest/server.ts` (Coolify-Service `ingest`, langlaufend, im Warehouse-Netz,
Bearer-gesichert). Endpunkte: `GET /pending/gutachten`, `POST /ingest/gutachten`,
`POST /ingest/kuerzung`, `/health`. Lokal end-to-end getestet. Details: **`n8n/README.md`**.
- **Phase 4** (`BHUg2f27aafCfI5Q`): Zeitplan → pending → OneDrive-Gutachten (Graph) →
  Parser → `POST /ingest/gutachten`.
- **Phase 5** (`4JgVp4tCzNHkPCpg`): Outlook-Anhang → **Mistral-OCR + LLM** →
  Pipedrive-Notiz + `POST /ingest/kuerzung` → `marts.v_durchsetzung_echt`.
- **Einrichtung (Inhaber):** Coolify — Domain auf Service `ingest` (Port 8080) +
  Secret `INGEST_TOKEN`. n8n — Credential „Warehouse Ingest" (Bearer) + Graph OAuth2.
  Dann Testlauf. Kein DB-Zugriff aus n8n nötig.

## NÄCHSTE SCHRITTE (Auswahl beim Neustart)

### Option A — Phase 4 (autoiXpert)  *(Unterbau gebaut & verifiziert; Architekturfrage offen)*
Plan + Stand: **`docs/plan-phase-4.md`** (§ „Stand 2026-07-15").

**Gebaut (typecheck grün, DSGVO-Filter gegen ZWEI echte Samples verifiziert — kein
Leak; noch NICHT in der Deploy-Kette):** `sql/009_raw_autoixpert.sql`,
`etl/autoixpert/{client,project,extract-gutachten,run-log}.ts`, npm `extract:gutachten`.
- API (Live-n8n): `GET …/externalApi/v1/reports/{id}`, **Bearer**. `token` =
  Aktenzeichen. `type` = Gutachtenart. `AUTOIXPERT_API_TOKEN` ist gesetzt.
- **Bonus LF2:** `insurance.organization_name` schließt die Versicherer-Lücke.
- Vermittler pseudonymisiert (kann natürliche Person sein), Dokument-Präsenz als
  Fachsignal (welche DAT-Kalkulation existiert).

**Zentraler Befund:** WBW/Restwert/Wertminderung/Reparaturkosten stehen **nicht in
der API — nur in den PDFs** (Inhaber bestätigt). Damit blockiert für LF8/LF10 die
**Architekturfrage: woher die Zahlen** (Plan §7: A vorerst ohne / B PDF-Parsing /
C evtl. Valuation-Endpunkt / D Pipedrive-Reparaturkosten). **Nächster Schritt =
diese Entscheidung**, dann `sql/010` (u. a. `v_versicherer_je_fall` für LF2 ist
schon jetzt baubar) + Golden + Deploy-Kette.

### Option B — Phase 5 (Kürzungsgrund / Durchsetzungsquote)  *(kein neuer Zugang nötig)*
Fundament steht (Phase 3 Positionen). Durchsetzungsquote = 1 − Σ Ausbuchung / Σ
Kürzung (Teilschuld/Haftungsquote raus). Braucht: Modellierung Kürzung je Position
vs. Ausbuchung; Plan `docs/plan-phase-5.md` erstellen (gegenlesen), dann bauen.

### Kleinaufgaben (jederzeit)
- Rest-`Sonstiges` (28) in `fixtures/positionskategorie.json` ergänzen, sobald der
  Inhaber die Namen zuordnet (Gestellung Werkstattausrüstung, Phantomkalkulation,
  „m. Bewertung", Tippfehler).
- n8n-Nightly aktivieren + Backup sauber lösen (s. o.).
