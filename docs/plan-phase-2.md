# Plan — Phase 2: Pipedrive → `fact_ausbuchung` → Metabase

**Status:** ENTWURF zum Gegenlesen. Datenmodellierung = die eigentliche Arbeit
dieser Phase; Code danach ist mechanisch. Bitte Abschnitt 9 (Entscheidungen) und
die Domänenregeln in Abschnitt 5 genau prüfen — hier entstehen sonst Zahlen, die
plausibel aussehen und falsch sind.

**Ziel:** Ein vollständiger, dünner Weg von der Quelle bis zur ersten Kennzahl.
Nicht verbreitern, bevor er steht.

---

## 1. Betriebsmodell / Auth (wichtig zuerst)

- `api.pipedrive.com` ist aus **meiner** Session gesperrt; `metabase.gollenstede.app`
  ist erreichbar. Der **produktive Extraktor läuft im Coolify-Container** (der
  erreicht Pipedrive) — nicht aus dieser Session.
- Der Extraktor authentifiziert per **read-only Pipedrive-Token** (REST v2),
  hinterlegt als **Coolify-Secret** `PIPEDRIVE_API_TOKEN` (+ `PIPEDRIVE_COMPANY_DOMAIN`).
  Der OAuth-MCP nutze **ich** nur zur Entwicklung (Fixtures ziehen) — er steht dem
  Cron-Container nicht zur Verfügung.
- Entwicklung/Test hier: echte Deals über den MCP in `fixtures/` ziehen, das
  Transform-SQL lokal gegen Postgres verifizieren (wie in Phase 1).

## 2. Scope

Deals (won/lost/open/archiviert) → `raw` → `core.fact_ausbuchung` (+ nötige
Dimensionen) → `marts.v_ausbuchung_monat` → **eine** Metabase-Frage. Dazu
Organisationen (für `dim_organisation`). Personen: **nicht** (Personenbezug).

## 3. Extraktoren

`etl/pipedrive/extract-deals.ts` und `etl/pipedrive/extract-organizations.ts`:

- **Inkrementell** über `updated_since`; Wasserstand in `raw._sync_state`
  (`source`, `last_updated_ts`, `last_run`).
- **Cursor-Pagination** vollständig durchlaufen (v2: `cursor`/`next_cursor`).
- **Alle Status:** won, lost, open, archiviert (verlorene Deals → Leitfrage 4).
- Flags `include_option_labels=true` + `include_labels=true`, damit Enum-Werte
  als `{id,label}` und `label_ids` als Objekte im Payload stehen (siehe 5.4 —
  ohne Metadaten-Endpoint ist das unsere Label-Quelle). Das bleibt „raw": es ist
  die unveränderte Antwort **dieser** Anfrage.
- **Rohantwort unverändert** als JSONB nach `raw.pipedrive_deals`
  (`id`, `payload`, `extracted_at`). Keine Transformation im Extraktor.
- **Rate Limits:** exponentielles Backoff, wiederaufnehmbar nach Abbruch.
- Zeitstempel als `timestamptz` in UTC; `local_*_date` **nicht** mit UTC
  verwechseln.

## 4. `raw`-Schema — `sql/002_raw.sql`

```
raw.pipedrive_deals         (id bigint PK, payload jsonb NOT NULL, extracted_at timestamptz NOT NULL)
raw.pipedrive_organizations (id bigint PK, payload jsonb NOT NULL, extracted_at timestamptz NOT NULL)
raw._sync_state             (source text PK, last_updated_ts timestamptz, last_run timestamptz)
```

`raw` ist heilig: nie überschreiben/transformieren/löschen. Upsert per `id`
(neuer `payload` ersetzt den alten Snapshot desselben Deals — Historie der
Rohantworten brauchen wir nicht, den letzten Stand schon).

## 5. `core`-Modellierung — `sql/003_core.sql`

**Entscheidung (siehe 9.1): `core` als VIEWS über `raw`.** Voll reproduzierbar,
kein Transform-Schritt, kein dbt — passt zur Projektgröße. Typisierung per Cast,
Validierung/Rejects als separate View.

### 5.1 `core.fact_ausbuchung` (Grain: ein Deal)

| Spalte | Herkunft (JSONB-Pfad) | Regel |
|---|---|---|
| `aktenzeichen` | `upper(regexp_replace(payload->>'title','\s','','g'))` | validiert `^\d{4}/\d+TG$`; Verstöße → `_rejects`, **nicht** still verwerfen |
| `deal_id` | `id` | |
| `deal_value_brutto` | `(payload->>'value')::numeric(12,2)` | **brutto** |
| `enthaltene_mwst` | `custom_fields->'8e0a…'->>'value'` | monetary-Objekt |
| `ausgebucht_betrag` | `custom_fields->'c4ae…'->>'value'` | **NULL bleibt NULL** (≠ 0!) |
| `ausgebucht_grund_id` | `custom_fields->'a037…'->>'id'` | FK `dim_ausbuchungsgrund` |
| `ist_erfasst` | `ausgebucht_betrag IS NOT NULL` | |
| `won_time` | `(payload->>'won_time')::timestamptz` | = Ausbuchungsdatum |
| `add_time` | `(payload->>'add_time')::timestamptz` | |
| `status` | `payload->>'status'` | |
| `org_id` | `(payload->>'org_id')::bigint` | FK `dim_organisation`; oft NULL |
| `sevdesk_rechnung_id` | `custom_fields->>'d886…'` | varchar (Join Phase 3) |

**Nicht** nach core: Kennzeichen (`00e9…`), Unfallhergang (`5831…`), Vor-/
Altschaden-Beschreibungen (`2b30…`, `5375…`) und alle weiteren Freitexte —
bleiben in `raw`. Die View selektiert nur die obigen Pfade; PII ist damit
strukturell ausgeschlossen (zusätzlich zur DB-Rechte-Sperre auf `raw`).

### 5.2 `core._rejects`

View: alle Deals, deren normalisierter Titel `^\d{4}/\d+TG$` **nicht** erfüllt,
mit `deal_id`, Rohtitel, Grund (`aktenzeichen_ungueltig`). Sichtbar, nicht still.

### 5.3 `dim_organisation`

Aus `raw.pipedrive_organizations`: `org_id`, `name` (juristische Person → Klartext
erlaubt), `typ` aus `label_ids` (35 → `versicherer`, 32 → `auftraggeber`, sonst
`unbekannt`). Fehlt `org_id` am Deal, zählt die Auswertung explizit als „ohne
Versicherer-Zuordnung" (nie coalescen).

### 5.4 `dim_ausbuchungsgrund`

Aus den im Payload eingebetteten `{id,label}` des Feldes `a037…` destilliert
(distinct). Bekannt: `70 = Nebenkosten`. **Bewusst nicht hartkodiert**; wächst
mit den Daten. In Phase 5 wird die Optionsliste aufs Kürzungsgrund-Enum
umgestellt (MENSCH).

### 5.5 `dim_datum`

Kalender-View (`generate_series`) mit Jahr/Monat/Quartal/ISO-Woche für die
Zeitachsen.

## 6. `marts.v_ausbuchung_monat`

Je Monat (`date_trunc('month', won_time)`) und `org_id`:
```
ausgebucht_summe = Σ ausgebucht_betrag         WHERE ausgebucht_betrag IS NOT NULL
basis_summe      = Σ deal_value_brutto         WHERE ausgebucht_betrag IS NOT NULL
ausbuchungsquote = ausgebucht_summe / NULLIF(basis_summe,0)
```
Ausschließlich über `ist_erfasst = true`. Organisationsname/-typ aus
`dim_organisation`.

## 7. Golden Dataset

`fixtures/golden-deals.json` — **20 handgeprüfte Deals**. Jeder ETL-/Transform-Lauf
assertet dagegen (eigener Test). Pflicht-Abdeckung: je ein Deal mit
`ausgebucht_betrag = 0`, `> 0 mit Grund`, `> 0 ohne Grund`, `NULL`, ein
verlorener Deal.

Vorgehen: **Ich baue einen Kandidatensatz aus echten Deals** (über den MCP,
inkl. der Pflichtfälle) mit den von mir berechneten Erwartungswerten. **Du prüfst
die 20 von Hand** — deine Werte sind die Wahrheit, nicht meine (Auftrag). Test-
Deals (z. B. Titel/Unfallhergang „test") schließe ich aus.

## 8. Verifikation (lokal, wie Phase 1)

Postgres hochziehen → Migrationen → Fixtures in `raw` laden → `core`/`marts`-Views
bauen → assert:
- Golden-Werte stimmen (Beträge, `ist_erfasst`, `aktenzeichen`).
- `NULL`-Ausbuchung bleibt `NULL`; taucht **nicht** in der Quote auf.
- Ungültige Aktenzeichen landen in `_rejects`.
- Quote reproduzierbar per Handrechnung auf dem Golden-Set.

## 9. Offene Entscheidungen

**9.1 `core` als Views** (statt materialisierter Tabellen mit PK). Empfehlung:
Views — reproduzierbar, wartungsarm, passend zur Größe. Eindeutigkeit von
`aktenzeichen` wird im Golden-Test statt per PK-Constraint geprüft. → ok?

**9.2 Read-only Pipedrive-Token** als Coolify-Secret bereitstellen (Produktion).
Ohne ihn läuft der Extraktor nur in meiner Dev-Umgebung über den MCP.

**9.3 Belastbarkeits-Datum der Ausbuchungshistorie.** Bekannt: 2024/Anfang 2025
überwiegend `NULL`. Ab welchem Datum ist die Historie belastbar? Alles davor
schneide ich in Auswertungen ab (nicht so tun, als wäre 2024 vollständig).

**9.4 Erste Metabase-Frage** kann ich nach dem Build **selbst** anlegen, weil
Metabase jetzt erreichbar ist — dafür bräuchte ich einen Metabase-API-Key als
Secret. Alternativ klickst du die eine Frage („Ausbuchungssumme je Organisation,
letzte 12 Monate") selbst. → wie hättest du es gern?

## 10. 🧑 MENSCH-Aufgaben (aus Auftrag)

- [ ] Read-only Pipedrive-Token + Company-Domain als Coolify-Secret.
- [ ] 20 Golden-Deals gegenprüfen (meine Kandidaten als Vorlage).
- [ ] Belastbarkeits-Datum festlegen (9.3).
- [ ] Erste Metabase-Zahl gegen dein Bauchgefühl prüfen; wirkt sie falsch, melden.

## 11. Reihenfolge des Baus

1. `002_raw.sql` + Extraktoren (Deals, Orgs) — inkl. lokalem MCP-Fixture-Zug.
2. `003_core.sql` (Views + Rejects + Dims).
3. `marts.v_ausbuchung_monat`.
4. Golden Dataset + Test, lokale Verifikation.
5. (nach Freigabe) Deploy-Notiz im RUNBOOK; Metabase-Frage.
