# STATUS — Arbeitsstand & nächste Schritte

Handoff für den Session-Neustart (Container ist ephemer; alles Wichtige ist
committet). **Zuerst diese Datei + `CLAUDE.md` lesen.**

## Branches (wichtig!) — aufgeräumt 2026-07-17

- **Main/Default:** `claude/bi-plattform-kfz-hxmpig` — jetzt auf aktuellem Stand
  (PR #2 gemergt, `ab0bc21`). = Trunk mit allem.
- **Designierter Arbeits-Branch:** `claude/status-md-next-step-blbeam` (Stand `a523eae`).
- **Deploy-Branch:** `claude/repo-deployment-setup-emf5b8` — **die Coolify-App
  `bi-etl-warehouse` deployt von diesem Branch.** FF-Push dorthin, dann UI-Deploy.
  → **Nach jedem Commit auf beide pushen:**
  `git push origin claude/status-md-next-step-blbeam` **und**
  `git push origin claude/status-md-next-step-blbeam:claude/repo-deployment-setup-emf5b8`.
- **Behalten:** `claude/phase-5-shortening-workflow-s6scak` (ungemergte Phase-5-Intake-Arbeit).
- **NOCH ZU LÖSCHEN — nur via GitHub-UI** (git-Proxy gibt weiterhin 403 auf
  `push --delete`, erneut geprüft 2026-07-17; GitHub-MCP hat kein Ref-Delete):
  `claude/sevdesk-phase-3-9a7g5k`, `claude/repo-deployment-setup-g24l0l`.

## ERLEDIGT (2026-07-17) — Metabase-Dashboards live (5 Dashboards, 16 Cards)

**5 Dashboards mit Cards in Metabase angelegt** (`https://metabase.gollenstede.app`,
Warehouse = database id **2**), Sammlung **„BI — Kfz-Sachverständigenbüro"**
(`/collection/5`). Alle 16 Cards laufen fehlerfrei gegen die Live-DB.
- **Key-Korrektur:** Der vorhandene `METABASE_API_KEY` (User `claude_gob_laptop_RW`)
  hat **volle Schreibrechte** (POST/PUT/DELETE /api/card + /api/dashboard) — ein
  separater `METABASE_ADMIN_KEY` war **nicht** nötig. Die frühere „query-only/403"-
  Annahme galt für einen älteren Key. `metabase_ro` (DB-Rolle) liest weiterhin nur
  core/marts.
- **Helfer:** `scratchpad/mbq.py` (native SQL via curl → /api/dataset),
  `scratchpad/build_dashboards.py` (idempotenter Builder: Sammlung/Dashboards per
  Name finden-oder-anlegen, Cards frisch, PUT `/api/dashboard/:id` dashcards).

**Die 5 Dashboards:**
1. **1 · Durchsetzung & Kürzungen** (LF2/3): Kürzung je Versicherer (row),
   Durchsetzungsquote je Versicherer (row), Durchsetzung je Fall sevDesk (row),
   Kürzungs-Diagnose Befund-Verteilung (row). Views `v_durchsetzung_sevdesk`,
   `v_durchsetzung_echt`, `v_kuerzung_echt_je_versicherer`, `v_kuerzung_sevdesk_diagnose`.
2. **2 · Gutachten & Totalschaden** (LF8/10): Totalschaden-/130%-Quote je Monat (combo,
   Quote auf rechter Achse), Honorar vs. Schadenhöhe (scatter, BVSK, >60k€ raus),
   Beurteilungs-Mix (pie), Ø Nutzungsausfall/Reparaturdauer je Kategorie (bar). Mix-
   Kategorie aus `ist_totalschaden`/`ueber_130_prozent`/`beurteilung='Bewertung'`
   (Freitext-`beurteilung` ist zu unsauber für direkte Gruppierung).
3. **3 · Umsatz & Zahlungsausfälle** (LF5): Umsatz je Monat gestapelt nach
   Positionskategorie (bar stacked), Umsatz je Kategorie (row), Forderungsverlust je
   Versicherer (row), Forderungsverlust je Monat (combo).
4. **4 · Einzugsgebiet (Geo)** (LF7): Umsatz/Fälle je PLZ-Gebiet (row, ohne
   „(unbekannt)"), Fälle je Ort (row, **DSGVO-Filter `anzahl_faelle >= 3`**,
   Kleinstfälle ausgeblendet). Geo live (Deploy `a523eae`), Coverage 457/881,
   Schwerpunkt PLZ 41/40/47 (Neuss/Düsseldorf/Krefeld).
5. **5 · Auftragseingang & Saisonalität** (LF9): Auftragseingang je Monat (bar),
   Saisonalität je Kalendermonat (bar, Ø/Jahr). **Go-Live-Import 2024-10 (372 Deals)
   per `add_time >= 2024-11-01` ausgeblendet**, sonst verzerrt er die Saisonkurve.

**DSGVO eingehalten:** nur core/marts-Views (kein raw); Ort-Chart auf ≥3 Fälle
aggregiert (kein identifizierender Einzelfall Ort+Kleinstzahl).

### Durchsetzungsquote ehrlich gemacht (`sql/028`, 2026-07-17)

**Befund auf Inhaber-Nachfrage:** Die Durchsetzungsquote war **nicht belastbar**.
Ursache = `1 − Ausbuchung/Kürzung` mit `COALESCE(ausbuchung,0)` → fehlender
Forderungsverlust-Beleg wurde zu „100 % durchgesetzt". Datenlage: **70 Schreiben
(alle aus OneDrive-Backfill; Live-WF `4JgVp4tCzNHkPCpg` hat bisher 0 geliefert —
pollt stündlich, findet keine neue Mail-Post)**, 39 mit Kürzungsbetrag, aber nur
**5** Aktenzeichen mit Overlap zu den 89 Forderungsverlust-Belegen → 22/25
Versicherer-Zeilen zeigten Schein-100 %. 46 sind Vor-Pipedrive-Altfälle (können gar
keinen Beleg haben). sevDesk-Methode zusätzlich mit Lesefehlern (Negativ-Quoten
bei Ausbuchung>Kürzung, `gezahlt_sv=0`, Extremwert 0525/1568TG DEVK 5.407 €).

**Fix `sql/028` (belastbar = `won` in `fact_ausbuchung`, Ausgang final):**
- `v_durchsetzung_echt`: Quote nur über abgeschlossene Fälle (12 statt 39); Altfälle
  fallen aus der Quote (bleiben als Betrag in `v_kuerzung_echt_je_versicherer`).
- `v_durchsetzung_sevdesk`: zusätzlich `won` + `gezahlt_sv>0` + Kürzung>1 € +
  Ausbuchung≤Kürzung (keine Negativ-Quoten mehr) → 10 saubere Fälle.
- `v_kuerzung_sevdesk_diagnose`: um Befunde erweitert (won offen, gezahlt_sv=0,
  inkonsistent). Verteilung: 38 Altfall · 10 verwertbar · 4 keine Kürzung · 2
  inkonsistent · je 1 won-offen/gezahlt_sv=0/Fehl-Lesung.
- **Dashboard 1 Cards live angepasst** (Inline-SQL gegen `core.*`, sofort korrekt
  vor Deploy): Card 42/43 als **Tabelle mit sichtbarem n**, Card 44 erweiterte
  Diagnose. `scratchpad/update_durchsetzung_cards.py`.
- **`sql/028` committet — wartet auf Coolify-UI-Deploy** (dann matcht die deployed
  Marts-Schicht die Cards). **Empfehlung an Inhaber:** für Entscheidungen die
  Forderungsverlust-Views (LF5, 89 echte Belege) nutzen; Durchsetzungsquote erst
  aussagekräftig, wenn Kürzung↔Ausbuchung fallweise breiter überlappen (nicht durch
  bloßes Warten auf den Live-WF, sondern durch Abdeckung beider Seiten).

### Rechtsanwalt/Kanzlei als Dimension — Versicherer × Anwalt (`sql/029`, 2026-07-17)

**Befund (Inhaber):** Der Rechtsanwalt je Fall steht im Deal-Custom-Field
`215832fc…` — die Feld-Doku hatte es **fälschlich als „Nutzungsausfall Tagessatz"**
geraten. Der Feldwert ist die **`org_id` der Kanzlei** (Fremdschlüssel auf dieselbe
`dim_organisation` wie der Versicherer). Damit ist **Versicherer × Anwalt kreuzbar**:
`deal.org_id` = Versicherer, `custom_fields[215832fc]` = Anwalt. Verifiziert an echten
Deals (152 = „Urbach + Urbach Rechtsanwälte", 128 = „Rechtsanwalt Philipp Nadler" …).
Anwalt-Coverage im Sample hoch (bei jungen Fällen oft gesetzt, während `org_id`/
Versicherer noch leer ist → teils bessere Abdeckung als der Versicherer).

**Gebaut `sql/029` (wartet auf Coolify-UI-Deploy):**
- `core.fact_ausbuchung` um `anwalt_org_id` erweitert (aus dem Custom-Field).
- `core.dim_anwalt`: 57 Kanzleien, **DSGVO-Whitelist per Namensmuster**
  (`rechtsanw|anwält|anwalt|kanzlei| & | und |partner|partg|mbb|gbr`) — trifft keine
  Privatperson (adressbehaftete Privatnamen wie „Belinda Wilke, Weingartstr…" bleiben
  außen vor). Kanzleien = juristische Personen, Klartext erlaubt.
- `marts.v_anwalt` (LF4: Umsatz + Fälle + won + Forderungsverlust je Kanzlei).
- `marts.v_versicherer_x_anwalt` (Kreuz-Matrix Fälle/Umsatz).
- Feld-Doku korrigiert: `docs/field-mapping.json` (label „Rechtsanwalt", confirmed) →
  `fields.generated.ts` regeneriert (`NUTZUNGSAUSFALL_TAGESSATZ` → `RECHTSANWALT`;
  Konstante war ungenutzt, Nutzungsausfall kommt aus den Gutachten-PDFs, nicht hier).
**DEPLOYT & Dashboard live (2026-07-17):** `sql/029` deployt (Commit 9d61398).
Coverage: **Anwalt 65 % (651/1001), Versicherer 74 %** — bei jungen Fällen Anwalt oft
gesetzt, Versicherer noch nicht. **Dashboard 7 „6 · Auftraggeber & Anwälte (LF4)"**
gebaut (4 Cards, Inline-SQL gegen `core.*`, `scratchpad/build_anwalt_dashboard.py`):
Auftraggeber-Ranking (Umsatz/Fälle/won/Forderungsverlust je Anwalt), Umsatz-Balken,
Fallzahl-Balken, **Versicherer×Anwalt Top-Kombinationen**. Top-Auftraggeber:
RA Claudia Busch (248 Fälle, 302 k€), RA Philipp Nadler (137, 160 k€), Peters
Rechtsanwälte (68, 85 k€).

- **DSGVO-Klärung (Inhaber):** Die „Privatpersonen"-Namen im Anwalt-Feld sind
  **durchweg Rechtsanwälte** (Einzelanwälte unter Klarnamen, öffentlich auffindbar),
  KEINE Geschädigten → Klartext erlaubt. Daher **`sql/030`**: die Kanzlei-Namens-
  Whitelist aus `sql/029` wieder entfernt, `dim_anwalt` = die vom Feld tatsächlich
  referenzierten Orgs (Name im Klartext). **`sql/030` wartet auf Coolify-UI-Deploy**
  (Dashboard nutzt bereits Inline-SQL → schon korrekt; Deploy gleicht nur die
  deployten Views `dim_anwalt`/`v_anwalt`/`v_versicherer_x_anwalt` an).
  ⚠️ `sql/029` NICHT nachträglich editieren — der Migrations-Runner ist checksum-
  basiert und bricht sonst ab; Korrekturen immer als neue Migration.
- **Backlog:** Kanzlei-Dubletten dedupen (z. B. „Beumer & Tappert" / „…und Tappert",
  „Wittenberg & Collegen" / „…und Kollegen"); Versicherer-Namen kanonisieren
  (Pipedrive-Org „HUK" vs „HUK Coburg Vers. AG" vs Brief „HUK…").

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
- **Phase 4** (`BHUg2f27aafCfI5Q`): Zeitplan → pending → OneDrive-Gutachten
  (**nativer OneDrive-Node**, Credential „Microsoft Drive account") → Parser →
  `POST /ingest/gutachten`. Fehlertolerant (`onError: continue`).
- **Phase 5** (`4JgVp4tCzNHkPCpg`, aktiv): Outlook-Anhang → **Mistral-OCR + LLM** →
  Pipedrive-Notiz + `POST /ingest/kuerzung` → `marts.v_durchsetzung_echt`.
  **+ Backfill-Zweig** „Backfill: Start" (manuell): OneDrive-Suche `Kürzung` →
  gleiche OCR→LLM→Ingest-Kette (historische Schreiben, `letter_key`-dedupliziert).

### Kürzungs-Backfill (2026-07-16) — via n8n-Reader, geladen über Deploy-Kette

OneDrive läuft über SharePoint; die Session hat **keinen** M365-Datei-Zugriff
(nur `get_me`), n8n hingegen schon (Credential **„Microsoft Drive account"**
`n0UiHatEWO28b1Uo`). Lösung: **n8n als Reader**, das Warehouse-Schreiben macht die
**Deploy-Kette** (kein Ingest-Dienst/Credential nötig).

- **Reader-Workflow** `qU8wCN2uqlgaz9rs` „Phase 5 Backfill — Schadenzahlung"
  (Quelle: `n8n/phase5-backfill-schadenzahlung.workflow.ts`): OneDrive-Suche
  **`Schadenzahlung`** → Batch-Download (3er, sonst OneDrive-Überlast) → Mistral-OCR
  → Mistral-LLM → Knoten „Sammeln". Ausgelesen über die **Production-Execution**
  (manuelle Executions inaktiver Workflows werden nicht gespeichert → Zeitplan +
  Publish + Production-Mode; danach unpublished).
- **Präzision:** Dateinamen sind unzuverlässig → gezielt „Schadenzahlung" (17 Treffer,
  7 echte Fälle in `…/Gutachten/JJJJ/MM/<az>/`, Rest private Konto-PDFs mit
  `folderAz=null` gefiltert). **Aktenzeichen aus dem Ordnerpfad**, nicht aus dem LLM
  (der verliest es oft). Aktenzeichen der 7: 1025/1742TG, 0825/1686TG, 1224/1434TG,
  0225/1506TG, 1223/1029TG, 0825/1683TG, 1122/694TG.
- **Echte Kürzung (Inhaber-Entscheidung):** `Kürzung = fakturiert (sevDesk/Deal)
  − gezahlt_sv (Brief)`. **Getrennt in drei Migrationen** (damit ein View-Fehler das
  Laden nicht blockiert / zur Fehler-Bisektion): `sql/019` upsertet die 7 Briefe nach
  `raw.kuerzungsschreiben`; `sql/020` legt `marts.v_kuerzung_sevdesk` an; `sql/021`
  `v_durchsetzung_sevdesk` (nur `plausibel` & Kürzung>0) + `v_kuerzung_sevdesk_diagnose`.
  Gegen Live-Daten geprüft: 0825/1683TG=390,51 · 1223/1029TG=185,01 · 1224/1434TG=0
  (voll) — die Methode fängt Fehl-Lesungen ab (0225/1506TG: gezahlt>fakturiert →
  `plausibel=false`).
- **Deploy-Falle (wichtig):** Coolify-API-Deploys (`/api/v1/deploy`) rekreieren den
  `etl`-One-Shot NICHT zuverlässig → `migrate` läuft nicht. **Nur der UI-Deploy**
  („Removing old containers → New container started") führt die Kette aus. Nach Push
  auf den Deploy-Branch also in der Coolify-UI deployen.
- **DEPLOYT & verifiziert (2026-07-16):** `fact_kuerzungsereignis=7`,
  `v_durchsetzung_sevdesk` mit 4 plausiblen Fällen (0825/1683TG **93,1 %**;
  1223/1029TG/0825/1686TG/1025/1742TG 100 %), Diagnose-View fängt die 3 Nicht-Fälle
  ab. Zwei Bugs unterwegs gefixt: crashender Ingest-Container vergiftete den Deploy
  (entfernt); Spaltennamen-Mismatch `fv.ausbuchung`/`ausgebucht` ließ `CREATE VIEW`
  in `021` scheitern (Bisektion über 019/020/021).
- **ERWEITERT & DEPLOYT (2026-07-17) — `sql/024`:** Reader jetzt
  über **6 Suchbegriffe** (Schadenzahlung/Kürzung/Regulierung/Ablehnung/Abrechnung/
  SVK) + **Dateiname-Whitelist**. Wichtiger Befund: OneDrive-Suche matcht auch
  Datei-INHALT → generische Terme trafen **1528** PDFs (Abtretungen/Widerrufe); der
  Whitelist-Filter (`Kandidaten`-Node) auf echte Versicherer-Schreiben schneidet auf
  **123 Kandidaten → 67 Kürzungsschreiben → 63 verwertbare Fälle**. `Stellungnahme`
  (unsere Erwiderung, kein Zahlbetrag) bewusst raus (eigene LF3-Quelle). Execution
  `1554241`. Datenqualität: `sachverstaendigenkosten` kommt mal Zahl, mal Objekt
  `{gezahlt,…}` → auf `gezahlt_sv` normalisiert.
  - **Coverage-Realität:** von den 63 sind nur **17 in `fact_ausbuchung`** (Pipedrive),
    davon **13 mit gezahlt_sv → sevDesk-Methode berechenbar** (+ die 7 aus `sql/019`).
    Die übrigen **46 sind vor-Pipedrive-Altfälle** (2019–2024) ohne sevDesk-Deal →
    nur über den **brief-expliziten `kuerzungsbetrag`** (Versicherer-Behauptung,
    Domänenmodell) abbildbar. Daher speichert `sql/024` **beide** Felder:
    `sachverstaendigenkosten` (50×, sevDesk-Methode) **und** `kuerzungsbetrag` (39×,
    echt-Views `v_durchsetzung_echt`/`v_kuerzung_echt_je_versicherer`).
  - **Inhaber-Entscheidung: Variante A** (alle 63, beide Methoden). **VERIFIZIERT
    live:** `fact_kuerzungsereignis=70` (7+63), `v_durchsetzung_sevdesk` 18 plausible
    Fälle (z. B. 0525/1568TG DEVK 5406,86 — sevDesk-fakturiert 6062,36 ≈ brief
    urspruenglich_gefordert 6062,34, unabhängige Quellen auf 2 ct deckungsgleich),
    Plausibilitäts-Bremse fängt 1 Fehl-Lesung (gezahlt>fakturiert). `v_kuerzung_echt_
    je_versicherer` (LF2) über alle Versicherer befüllt inkl. der 46 Altfälle.
  - **Reader nach Backfill unpublished** (sonst OCR-t der Zeitplan nächtlich alle 123).
  - **Offen/Ausbau:** `Stellungnahme`-Schreiben (108×) als eigene LF3-Quelle
    (setze ich Kürzungen per Stellungnahme durch?) noch nicht erfasst.

### Phase 4 (Gutachten 2026) — M365-Direktroute, `sql/025`, wartet auf Deploy-Freigabe (2026-07-17)

Der M365-Connector zeigt inzwischen **SharePoint-Tools** (`sharepoint_search`,
`read_resource`) — vorher nur `get_me`. Damit lassen sich Gutachten-PDFs **direkt** aus
SharePoint lesen (voller Textlayer, **kein OCR, kein n8n**). Genutzt, um die 2026-Lücke
des Volllaufs (`sql/023`) zu schließen.
- **150 offene 2026-won-Fälle** (in `fact_ausbuchung`, nicht in `fact_gutachten`) geprüft:
  **120 mit Gutachten/Bewertung gefunden & geparst** (86 Reparatur-, 26 Totalschaden,
  8 Bewertung), 30 ohne abgelegtes Gutachten (nur Rechnung/Werkstatt/WBW — sehr junge Fälle).
- **Extraktion über isolierte Subagenten** (Suche → `read_resource` → Zusammenfassung
  parsen → nur 9 Whitelist-Zahlenfelder). DSGVO: VIN/Kennzeichen/Klarnamen NIE persistiert.
  Validierung: 120/120 mit exakt den 9 Keys, alle netto×1,19≈brutto, jede Totalschaden-
  Beurteilung deckt sich mit reparaturkosten_brutto>WBW.
- **Lernpunkt Concurrency:** 14 Subagenten parallel drosseln MS-Graph (429, 50 RPM shared).
  Fix: max. ~4 gleichzeitig, sequentiell je Agent, nie `sleep` (Harness bricht ab),
  bei 429 skip-and-retry. Damit sauber durchgelaufen.
- **`sql/025`** = 120 Fälle, Upsert `raw.gutachten_fachwerte`. Committet; **wartet auf
  Deploy-Freigabe** (FF auf Deploy-Branch). Danach `fact_gutachten` ≈ 471+120 = 591.

### Phase 4 (Gutachten-Fachwerte) — Reader gebaut, 11 Fälle live (2026-07-16)

Kein Ingest mehr; **n8n-Reader** liest je Aktenzeichen aus OneDrive und lädt via
Migration. **Befund:** auch Archive (<2026, Fremdprogramm „Altova StyleVision")
haben eine **Textebene** und exakt das „Zusammenfassung des Gutachtens"-Format →
**kein OCR**, nur **3 Seiten** (`maxPages:3`), quasi kostenlos; der Crown-Jewel-
Regex-Parser passt.
- **Reader** `Qu9rKyRoMbQ6cxTx` „Phase 4 — Gutachten Fachwerte (Per-Fall, 3 S.)":
  Fälle → je Aktenzeichen OneDrive-Suche (Aktenzeichen **ohne Slash**, sonst „Bad
  request"; `alwaysOutputData` sonst stoppt der Batch-Loop) → Gutachten-PDF wählen →
  Download → PDF-Text 3 Seiten → LLM/Regex → Sammeln (`textLen`-Gate gegen LLM-
  Halluzination). Ausgelesen über die laufende Execution.
- **DEPLOYT & verifiziert:** `sql/022` = **11 validierte Fälle** → `core.fact_gutachten`
  (Totalschaden/130-% korrekt), `marts.v_totalschaden_quote` (LF10),
  `v_honorar_vs_schaden` (LF8, join auf sevDesk-Grundhonorar).
- **VOLLLAUF FERTIG (2026-07-16):** Execution `1554143` über alle **881 won-Fälle**
  gelaufen (status `success`, ~7 h, überstand einen n8n-DB-Restart ohne Datenverlust).
  Ergebnis inkrementell aus dem `Sammeln`-Node geharvestet (Execution-Daten werden
  bei Erfolg verworfen → währenddessen mitlesen). **`sql/023_backfill_gutachten_full.sql`
  = 468 Gutachten** (Trefferquote 468/881 ≈ 53 %; Rest = junge 2026-Fälle noch nicht
  in OneDrive + 5 PDFs ohne Fachwerte-Summary, bewusst verworfen). Datenqualität:
  alle Aktenzeichen valide, keine Dubletten, **0 unplausible netto→brutto-Ratios**
  (alle ≈ 1,19). Endstand `raw.gutachten_fachwerte` nach Deploy = **471 distinct**
  (468 aus 023 + 3 nur in 022 gefundene Archive). **Committet auf Arbeits-Branch;
  wartet auf Freigabe für FF-Push auf Deploy-Branch.**
- **Offen/Ausbau:** nur die erste präzise Scheibe. Weitere Kürzungen heißen anders
  (`Vers Ablehnung SVK`, Versicherer-Namen) oder kamen per Mail → Suchbegriffe im
  Reader erweitern; ambige Fälle (0825/1686TG, 1025/1742TG *open*) im Diagnose-View
  nachbessern. `fact_gutachten` (Phase 4) weiter offen.

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
