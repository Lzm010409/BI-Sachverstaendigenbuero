# `fixtures/` — Referenzdaten (Golden Dataset & Seeds)

Handgeprüfte Daten für Tests und für pflegbare Klassifikationen.

## Dateien

| Datei | Zweck |
|---|---|
| `golden-deals.json` | **Golden Dataset**: handverlesene Pipedrive-Deals mit bekannten Erwartungswerten. Von `scripts/load-golden.ts` → `raw` geladen, von `test-golden.ts` gegen `core`/`marts` geprüft. Verifiziert die Transformationslogik ohne Prod. |
| `golden-deals-review.md` | Menschliche Durchsicht/Begründung zum Golden Dataset (welcher Fall prüft was). |
| `sevdesk-sample.json` | Beispiel-Rechnung(en) mit Positionen für `test-sevdesk.ts` (Positionskategorie-/Konsistenzlogik). |
| `positionskategorie.json` | **Editierbarer Seed** der Positionskategorie-Regeln. |

## Positionskategorie-Seed — so wird gepflegt

`positionskategorie.json` bildet sevDesk-Positionsnamen auf Kategorien ab
(Grundhonorar, Fotokosten, Fahrtkosten …). Pflege-Workflow:

1. `positionskategorie.json` editieren (neue Regel/Alias ergänzen).
2. Deploy → `etl/sevdesk/load-kategorien.ts` lädt den Seed nach
   `core.dim_positionskategorie_regel` (`sql/008`).
3. Die Kategorie-Views nutzen die Regeltabelle → Rest-„Sonstiges" schrumpft.

Das ist das Muster für „vom Inhaber pflegbare Klassifikation": Seed-Datei editieren →
redeploy, kein Code nötig.

> Hinweis: Golden/Sample enthalten Testdaten — die echten Domänenregeln stehen in
> `CLAUDE.md`, nicht hier.
