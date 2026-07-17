# `etl/autoixpert/` — autoiXpert-Gutachten-API (Phase 4, Unterbau)

Anbindung an die autoiXpert **externalApi** (`GET …/externalApi/v1/reports/{id}`,
Bearer-Auth, `token` = Aktenzeichen). Gebaut und typecheck-grün, DSGVO-Filter gegen
echte Samples geprüft — **aber noch NICHT in der Deploy-Kette** (aus der Web-Session
ist der autoiXpert-Egress per Netzwerk-Policy geblockt; Dauerbetrieb liefe in
Coolify/n8n).

## Dateien

| Datei | Rolle |
|---|---|
| `client.ts` | REST-Client (Bearer, `AUTOIXPERT_API_TOKEN`). |
| `extract-gutachten.ts` | Reports je Aktenzeichen → `raw.autoixpert` (`sql/009`). npm: `extract:gutachten`. |
| `project.ts` | DSGVO-Whitelist (Vermittler pseudonymisiert; Dokument-Präsenz als Fachsignal). |
| `run-log.ts` | Lauf-Protokoll → `marts.v_etl_run`. |

## Wofür relevant

- **Bonus LF2:** `insurance.organization_name` schließt die Versicherer-Lücke
  (saubere Versicherer-Zuordnung je Fall).
- **Zentraler Befund:** WBW/Restwert/Wertminderung/Reparaturkosten stehen **nicht in
  der API**, nur in den PDFs → dafür ist der Weg über `etl/gutachten` + n8n
  (PDF-Parsing) die produktive Lösung. Die autoiXpert-API bleibt v. a. für die
  Versicherer-Zuordnung interessant.

Status/Entscheidungen: `docs/plan-phase-4.md`, `docs/status-phase-4.md`.
