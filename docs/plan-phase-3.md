# Plan Phase 3 — sevDesk positionsscharf

Status: **Entwurf, zum Gegenlesen.** Noch nicht gebaut. Bei Datenmodellierung
ist der Plan die Arbeit — erst gegenlesen, dann bauen.

---

## 0. Ziel & Bezug zu den Leitfragen

Rechnungsdaten **positionsscharf** aus sevDesk ins Warehouse: die einzelnen
Positionen einer Gutachtenrechnung (Grundhonorar, Nebenkosten wie Fahrtkosten,
Schreibkosten, Fotokosten, Porto/Telefon, ggf. Restwertrecherche …), jeweils
mit Menge, Einzelpreis (brutto), Summe und Steuersatz.

**Warum:** Fundament für **Phase 5 (Kürzungsgrund)**. Ein Versicherer kürzt
typischerweise *einzelne Positionen* („Fahrtkosten von 45 € auf 25 €"). Ohne die
Positionen lässt sich eine Kürzung keinem Grund zuordnen. Zahlt damit indirekt
auf **Leitfrage 2/3** (welche Position wird wie oft gekürzt, lohnt die
Stellungnahme) und liefert die Basis für **Leitfrage 8** (Honorar vs.
Schadenhöhe, BVSK-Korridor).

**Nicht Ziel:** keine Netto-Umrechnung (alles bleibt brutto); kein
Zahlungsstatus aus sevDesk (die Ausbuchung/Zahlung ist und bleibt die Wahrheit
aus Pipedrive — sevDesk liefert das *Soll* je Position, nicht das *Ist* der
Zahlung).

---

## 1. Betriebsmodell / Auth

- Read-only sevDesk-API-Token als Coolify-Secret **`SEVDESK_API_TOKEN`** (analog
  Pipedrive). Der Token existiert bereits als n8n-Credential „SevDesk"; für den
  ETL-Container muss derselbe Wert als Coolify-Secret hinterlegt werden.
- Extraktor läuft im Coolify-Container (`etl`-Service, analog den Pipedrive-
  Extraktoren). Basis-URL `https://my.sevdesk.de/api/v1`.
- Auth: `api_token`-Query-Parameter (gleiches Muster wie der Pipedrive-Client)
  bzw. `Authorization`-Header. **Nur GET** (read-only).
- API-Details vor dem Bau final gegen die aktuelle sevDesk-Doku prüfen
  (`Invoice`, `InvoicePos`, `Invoice/{id}/getPositions`, Filter nach
  Änderungsdatum). Nie aus dem Gedächtnis.

---

## 2. Join & Datenfluss

- **Link:** `core.fact_ausbuchung.sevdesk_rechnung_id` (aus Pipedrive-Feld
  `d886…`) → sevDesk **Invoice-Objekt-ID**. Bestätigt durch die Deeplinks
  (`ee8bc622…` = `…/RE/id/<zahl>`), die auf dieselbe ID zeigen — es ist die
  Objekt-ID, **nicht** die Rechnungsnummer.
- **Extraktion (Vorschlag):**
  1. Erststart = Vollabzug: `GET /Invoice?limit=…&offset=…` über alle Rechnungen
     (belastbar ab 2024, s. STATUS).
  2. Positionen je Rechnung: `GET /InvoicePos?invoice[id]=<id>&invoice[objectName]=Invoice`
     (bzw. `Invoice/{id}/getPositions`) — im Bau die effizientere Variante wählen.
  3. Danach inkrementell über `raw._sync_state` (Filter nach Änderungsdatum der
     Rechnung), analog Pipedrive.

---

## 3. DSGVO — kritischer Punkt (Entscheidung nötig)

sevDesk-Rechnungen enthalten den **Rechnungsempfänger** (Kontakt) — oft eine
**natürliche Person** (der Geschädigte) mit Klarname und Adresse. Das darf laut
CLAUDE.md **nicht** ins Warehouse.

Das steht in Spannung zu „raw ist heilig / unverändert". Auflösung analog zur
bestehenden Pipedrive-Regel („Freitextfelder mit Personenbezug nicht
übernehmen"):

- **Option A (Empfehlung):** Personenbezug gar nicht erst persistieren. In
  `raw.sevdesk_*` nur die analysenotwendigen Felder (Positionen, Beträge,
  Steuersätze, Rechnungs-ID, Datum, Rechnungsnummer). Kontakt-Klartext wird
  **vor** dem Schreiben verworfen. Bricht „raw unverändert" bewusst zugunsten
  DSGVO — konsistent mit der Pipedrive-Freitextregel.
- **Option B:** Kontaktbezug beim Ingest pseudonymisieren (Hash-ID).

Zusätzlich: **Positions-Freitext prüfen** — im Positionstext stehen gelegentlich
Kennzeichen/Namen. In der Auswertung nur die **Kategorie** verwenden, nicht den
Rohtext ungefiltert exponieren.

---

## 4. Schema (raw)

```
raw.sevdesk_invoices           (id bigint PK, payload jsonb NOT NULL, extracted_at timestamptz NOT NULL)
raw.sevdesk_invoice_positions  (id bigint PK, invoice_id bigint NOT NULL, payload jsonb NOT NULL, extracted_at timestamptz NOT NULL)
```

`payload` bereits DSGVO-gefiltert (s. 3). Inkrementell über `raw._sync_state`
(neue Quellen `sevdesk_invoices`). Migration `sql/005_raw_sevdesk.sql`.

---

## 5. core / marts

- **`core.fact_rechnungsposition`** (View über raw): `invoice_id`, `aktenzeichen`
  (Join über `fact_ausbuchung` / Deals per `sevdesk_rechnung_id`), `position_id`,
  `kategorie_id`, `menge`, `einzelpreis_brutto`, `summe_brutto`, `steuersatz`.
- **`core.dim_positionskategorie`** — datengetrieben (wie `dim_ausbuchungsgrund`):
  mappt sevDesk-Positionsnamen auf einen **kontrollierten Katalog**
  (Grundhonorar, Fahrtkosten, Schreibkosten, Fotokosten, Porto/Telefon,
  Restwertrecherche, …). Katalog mit dem Inhaber abstimmen.
- **marts:** z. B. `v_rechnungsposition_monat`, `v_position_je_kategorie`.
  Genaue Views nach Bedarf für Phase 5.

---

## 6. Golden / Verifikation

- Golden-Set erweitern: für einige der 20 bekannten Deals die sevDesk-Positionen
  gegenprüfen. **Konsistenzcheck klären:** Summe der Positionen (brutto) ==
  Rechnungssumme == Pipedrive `deal_value_brutto`? (Erwartung mit Inhaber
  bestätigen — davon hängt ein harter Assert ab.)
- read-only, produktionssicher, analog `test:golden`.

---

## 7. Offene Fragen an den Inhaber

1. **DSGVO:** Option A (Personenbezug gar nicht speichern) oder B (Hash)?
2. **Positionskategorien:** Welche Kategorien sind für die Kürzungsanalyse
   relevant / wie sollen sevDesk-Positionsnamen gebündelt werden?
3. **Konsistenz:** Ist die Rechnungssumme (brutto) == Pipedrive `deal_value`?
   (Für den Golden-Assert.)
4. **Token:** read-only `SEVDESK_API_TOKEN` als Coolify-Secret bereitstellen.

---

## 8. Reihenfolge / Checkliste

- [x] Branch (`claude/sevdesk-phase-3-9a7g5k`)
- [x] sevDesk-Struktur an echter Rechnung verifiziert (Inhaber-Sample, Az 0726/2012TG)
- [ ] `SEVDESK_API_TOKEN` als Coolify-Secret an der ETL-Ressource *(beim Deploy)*
- [x] `sql/005_raw_sevdesk.sql` (raw-Tabellen)
- [x] `etl/sevdesk/{client,project,extract-invoices,extract-positions}.ts` (DSGVO-Filter Option A)
- [x] `sql/006_core_sevdesk.sql` (fact_rechnungsposition, dim_positionskategorie, marts)
- [x] Golden erweitert (`fixtures/sevdesk-sample.json`, `scripts/{load,test}-sevdesk.ts`) + lokal grün
- [x] `etl`-Deploy-Service um sevDesk-Extraktion ergänzt (+ `sevdesk-test`, profile manual)

**Erledigt-Notiz (2026-07-15):** lokal end-to-end verifiziert (Postgres 16,
Migrationen 001–006, `test:sevdesk` grün, Konsistenz `differenz=0`, DSGVO-Grants ok).
Offen: Deploy + Cross-System-Assert (`sumGross` == Pipedrive `deal_value`) + Katalog-
Review mit dem Inhaber. Konsistenzcheck aus §6 (Σ Positionen == Rechnungssumme) ist
**bestätigt**.
