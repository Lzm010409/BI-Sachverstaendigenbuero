# n8n-Workflows (versioniert)

SDK-Quellcode der n8n-Workflows dieses Projekts. Angelegt/aktualisiert über den
n8n-MCP; hier versioniert.

## Architektur: n8n → HTTP-Ingest → Warehouse

**n8n und die Warehouse-DB sind NICHT im selben Netz** — n8n kann Postgres nicht
erreichen. Daher schreiben (und lesen) die Workflows über einen kleinen
**HTTP-Ingest-Dienst** (`etl/ingest/server.ts`), der im Warehouse-Netz läuft
(Coolify-Service `ingest`, s. `docker-compose.yml`) und über eine öffentliche
Coolify-Domain erreichbar ist. Auth: `Authorization: Bearer $INGEST_TOKEN`.

**Endpunkte:** `GET /pending/gutachten` (Arbeitsliste), `POST /ingest/gutachten`,
`POST /ingest/kuerzung`, `GET /health`.

**Einmalige Einrichtung (Coolify + n8n):**
1. **Coolify:** Service `ingest` deployt mit der Ressource. Eine **Domain** darauf
   legen (z. B. `ingest.gollenstede.app` → Port 8080) und **Secret `INGEST_TOKEN`**
   setzen. (In den Workflow-Dateien ist `https://ingest.gollenstede.app` als Basis
   hinterlegt — bei anderer Domain dort + in den n8n-HTTP-Nodes anpassen.)
2. **n8n:** Credential **„Warehouse Ingest"** (Typ *Bearer*, Wert = `INGEST_TOKEN`)
   an den HTTP-Nodes „…(HTTP)". Damit entfällt jeder DB-Zugriff aus n8n.

## phase4-gutachten-fachwerte.workflow.ts
**n8n-ID:** `BHUg2f27aafCfI5Q` · https://n8n-coolify.gollenstede.app/workflow/BHUg2f27aafCfI5Q

Zeitplan → `GET /pending/gutachten` (offene Fälle) → je Fall Gutachten in OneDrive
suchen (**nativer OneDrive-Node**) → Download → Text extrahieren → Fachwerte-Parser
(Code, identisch zu `etl/gutachten/parse-fachwerte.ts`) → `POST /ingest/gutachten` →
`raw.gutachten_fachwerte` → `core.fact_gutachten` (`sql/016`).
**Credentials:** „Microsoft Drive account" (OneDrive, hinterlegt) + „Warehouse Ingest".
**Prüfen:** OneDrive-Suchtreffer je Aktenzeichen (Ordner-/Dateibenennung), Testlauf.
Die OneDrive-/Extract-/Ingest-Nodes sind fehlertolerant (`onError: continue`), damit
ein fehlendes Gutachten den Batch-Loop nicht anhält.

## phase5-kuerzungsschreiben.workflow.ts
**n8n-ID:** `4JgVp4tCzNHkPCpg` · https://n8n-coolify.gollenstede.app/workflow/4JgVp4tCzNHkPCpg

**Intake (umgebaut 2026-07-16): app-only Graph-Poll des GETEILTEN Postfachs
`abrechnungsschreiben@gollenstede-sachverstand.de`.** Der frühere Outlook-Trigger
(`microsoftOutlookTrigger`) war *delegiert* und sah nur das eigene Postfach des
angemeldeten Nutzers → das geteilte Postfach blieb unerreichbar. Neu:
`Schedule (stündlich)` → `Graph: Mails auflisten` (`GET /users/<mb>/mailFolders/inbox/
messages?$filter=isRead eq false and hasAttachments eq true`) → `Mails aufteilen` →
`Graph: Anhänge holen` → `Anhang → Files (Graph)` (erster PDF-Anhang, base64 → binary
`Files`) → **Mistral-OCR** → **Mistral-LLM** (Structured-Output) → wenn
Kürzungsschreiben: **Pipedrive-Notiz am Deal** + `POST /ingest/kuerzung` →
`raw.kuerzungsschreiben` → `core.fact_kuerzungsereignis` + `marts.v_durchsetzung_echt`
(`sql/017`/`018`). Seitenzweig `Graph: Als gelesen markieren` (PATCH `isRead=true`) =
Dedup, `onError=continue`.

**Auth (app-only, NICHT delegiert):** generische n8n-Credential **„Microsoft Graph
App-Only"** (Typ *OAuth2 API*), Grant Type **Client Credentials**, Token-URL
`https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token`, Scope
`https://graph.microsoft.com/.default`. Der Zugriff ist per **RBAC for Applications**
(Exchange Online) auf genau dieses eine Postfach begrenzt: Rolle `Application Mail.Read`
(lesen) + `Application Mail.ReadWrite` (Als-gelesen-Markieren/Dedup). Die
Graph-Security-Credential (`microsoftGraphSecurityOAuth2Api`) ist **delegiert** und hier
**nicht** verwendbar.
**Weitere Credentials:** Mistral Cloud, Pipedrive (auto-zugewiesen) + „Warehouse Ingest".

**Go-live-Schritte:** (1) Credential „Microsoft Graph App-Only" anlegen; (2) an den
3 Graph-Nodes binden; (3) Application-Rolle `Mail.ReadWrite` ergänzen (sonst kein
Dedup); (4) Trigger „Stündlich Abrechnungspostfach" aktivieren (ist bewusst noch
deaktiviert). Der alte Trigger „Neue Mail mit Anhang" ist deaktiviert.

**Backfill (gebaut):** Trigger „Backfill: Start" (manuell) → nativer OneDrive-Node sucht
`Kürzung`-PDFs → Filter → Download (binary `Files`) → **gleiche** OCR→LLM→Pipedrive+
Warehouse-Kette. Credential: „Microsoft Drive account". Dedupliziert über `letter_key`.

**Manueller Upload:** zusätzlicher Form-Trigger „On form submission" (Datei-Upload)
speist ebenfalls in die OCR-Kette.
