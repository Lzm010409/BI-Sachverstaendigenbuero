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
suchen (Graph) → PDF laden → Text extrahieren → Fachwerte-Parser (Code, identisch zu
`etl/gutachten/parse-fachwerte.ts`) → `POST /ingest/gutachten` → `raw.gutachten_fachwerte`
→ `core.fact_gutachten` (`sql/016`).
**Credentials:** Microsoft Graph OAuth2 (`Files.Read.All`) + „Warehouse Ingest".
**Prüfen:** OneDrive-Pfad (persönlich vs. SharePoint-Site), Testlauf.

## phase5-kuerzungsschreiben.workflow.ts
**n8n-ID:** `4JgVp4tCzNHkPCpg` · https://n8n-coolify.gollenstede.app/workflow/4JgVp4tCzNHkPCpg

Outlook-Trigger (neue Mail mit Anhang) → Anhang→`data` → **Mistral-OCR** → **Mistral-
LLM** (Structured-Output) → wenn Kürzungsschreiben: **Pipedrive-Notiz am Deal** +
`POST /ingest/kuerzung` → `raw.kuerzungsschreiben` → `core.fact_kuerzungsereignis` +
`marts.v_durchsetzung_echt` (`sql/017`/`018`).
**Credentials:** Outlook, Mistral Cloud, Pipedrive (von n8n **auto-zugewiesen**) +
„Warehouse Ingest".
**Prüfen:** OCR-Ausgabefeld (Prompt bekommt robust den ganzen OCR-Output), Aktenzeichen-
Treffer in Pipedrive.

**Nächster Ausbau:** Kürzungsschreiben-Backfill über die OneDrive-Fallordner (zweiter
Trigger, gleiche Verarbeitung).
