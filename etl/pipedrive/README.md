# `etl/pipedrive/` — Pipedrive-Extraktoren

Pipedrive ist das **Stammsystem** des Falls. Der Deal-Titel **ist** das Aktenzeichen
(`MMJJ/NummerTG`) — der Join-Key über alle Systeme.

## Dateien

| Datei | Was |
|---|---|
| `client.ts` | REST-Client. Auth = `api_token`-Query-Parameter, **API v2** (`/api/v2/<resource>`), cursor-/offset-Pagination, Backoff. |
| `extract-deals.ts` | alle Deals → `raw.pipedrive_deals` (JSONB). Basis für `core.fact_ausbuchung`. |
| `extract-organizations.ts` | Organisationen → `raw.pipedrive_organizations`. Typ aus `label_ids` (35 = Versicherer, 32 = Auftraggeber/Anwalt/Privat). |
| `extract-persons.ts` | Geschädigte — **nur Geo** (PLZ-Gebiet + Ort) → `raw.pipedrive_person_geo`. Kein Name/keine Straße (DSGVO). |
| `fields.generated.ts` | **generierte** Konstanten für die Custom-Field-Hash-Keys. |

## Custom-Fields — nie raten

Custom Fields haben undurchsichtige Hash-Keys. Zugriff **ausschließlich** über die
Konstanten in `fields.generated.ts`. Diese Datei wird **generiert** aus
`docs/field-mapping.json` (`npm run generate:fields`) — **nie von Hand editieren**.
Neues/korrigiertes Feld → `field-mapping.json` pflegen → regenerieren.

Beispiele bestätigter Felder: Ausgebucht Betrag/Grund, enthaltene MwSt,
sevDesk-Rechnungs-ID, autoiXpert-Gutachten-ID, **Rechtsanwalt** (`215832fc…`, Wert =
`org_id` der Kanzlei — Join für LF4/Versicherer×Anwalt).

## Wichtige Domänen-Fakten

- Pipeline `2`, Stages 6→11 (`10 Bezahlt/Won` = Fall abgeschlossen, `won_time` =
  Ausbuchungsdatum).
- `deal.label_ids` mischt Gutachtenart (28 Haftpflicht, 36 Bewertung), Fall-Alterung
  (61–63) und Fall-Flags (60 = OHNE RECHTSANWALT) → im ETL/Views trennen.
- `deal.org_id` = Versicherer (wenn gesetzt, ~74 % Coverage); der Anwalt hängt am
  Custom-Field `215832fc…`, nicht am `org_id`.

## DSGVO

Personen (Geschädigte) sind natürliche Personen → **nur** pseudonyme Geo-Daten
(`extract-persons.ts`) landen im Warehouse. Freitextfelder (Unfallhergang,
Schadenbeschreibung), Kennzeichen und VIN werden **nicht** übernommen.
