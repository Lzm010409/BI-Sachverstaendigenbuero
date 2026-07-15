# Plan Phase 4 — autoiXpert (Fachdaten: WBW, Restwert, Wertminderung …)

Status: **Entwurf, zum Gegenlesen.** Noch nicht gebaut. Bei Datenmodellierung ist
der Plan die Arbeit — erst gegenlesen, dann bauen.

---

## 0. Ziel & Bezug zu den Leitfragen

Die **Fachdaten des Gutachtens** aus autoiXpert ins Warehouse: vor allem
**Wiederbeschaffungswert (WBW)**, **Restwert** und **Wertminderung (merkantiler
Minderwert)** — plus Schadenhöhe/Reparaturkosten und die Totalschaden-/130-%-
Einordnung.

**Warum:** Diese Werte fehlen bisher. Pipedrive liefert schon Reparaturkosten
(`adb0956f` brutto / `4ceb3674` netto) und Nutzungsausfall-Tagessatz (`215832fc`),
aber **nicht** WBW, Restwert, Wertminderung. Genau die braucht es für:

- **Leitfrage 8** — Honorar (aus sevDesk, Phase 3) gegenüber **Schadenhöhe**
  (BVSK-Honorarkorridor). Ohne Schadenhöhe/WBW kein Korridor.
- **Leitfrage 10** — **Totalschaden-/130-%-Quote** und Korrelation mit Kürzungen.
  Totalschaden = Reparaturkosten > WBW; 130-%-Fall = Reparatur zwischen WBW und
  130 % WBW. Braucht WBW + Reparaturkosten + Restwert.

**Nicht Ziel:** keine zusätzliche Auftragsart (bestätigt: nur Haftpflicht +
Bewertung; autoiXpert liefert Fachdaten, keine neue Gutachtenart). Keine Freitexte,
kein Personenbezug (s. DSGVO).

---

## 1. Betriebsmodell / Auth

- Read-only autoiXpert-API-Token als Coolify-Secret **`AUTOIXPERT_API_TOKEN`**
  (analog Pipedrive/sevDesk). In n8n existieren Credentials „AutoIXPert Bearer
  Token" (`httpBearerAuth`) und „AutoIxpert Header Auth" (`httpHeaderAuth`) — der
  passende Wert muss als Coolify-Secret hinterlegt werden.
- Basis-URL aus dem Deeplink ablesbar: `app.autoixpert.de` (Gutachten unter
  `/Gutachten/<id>`). **API-Endpunkt, Auth-Schema und Feldnamen vor dem Bau final
  gegen die aktuelle autoiXpert-Doku prüfen** — nie aus dem Gedächtnis. Nur GET.
- Extraktor läuft im Coolify-`etl`-Container (analog sevDesk-Extraktoren).

---

## 2. Join & Datenfluss

- **Link:** Pipedrive-Deal-Feld **`f6970a4f…` (autoiXpert-Gutachten-ID)** →
  autoiXpert-Gutachten. Liegt bereits in `raw.pipedrive_deals`. Das **Aktenzeichen**
  kommt vom Deal (nicht aus autoiXpert), damit Join zu allen anderen Fakten steht.
- **Extraktion (Vorschlag):** nicht alle autoiXpert-Gutachten blind ziehen, sondern
  über die **Deals mit gesetzter Gutachten-ID** iterieren (aus `raw.pipedrive_deals`)
  und je ID das Gutachten holen. Vorteil: nur relevante, dem Aktenzeichen zuordenbare
  Gutachten; automatisch auf den Bestand ab 2024 beschränkt.
- Inkrementell später über `raw._sync_state` (neue Quelle `autoixpert_gutachten`).

---

## 3. DSGVO — kritischer Punkt (Option A, wie sevDesk)

autoiXpert ist **personenbezugs-schwer**: Geschädigten-Klarname, Anschrift, **VIN**,
**Kennzeichen**, Freitexte (Unfallhergang, Schadenbeschreibung). Nach CLAUDE.md
**dürfen VIN und Kennzeichen gar nicht ins Warehouse**, Freitexte ebenso wenig.

- **Option A (wie Phase 3):** Personenbezug gar nicht erst persistieren. Der
  Extraktor projiziert **vor** dem Schreiben auf eine Whitelist: nur die numerischen
  Fachwerte, Gutachtenart, Datumsfelder, Fahrzeug-**Klassenmerkmale ohne Bezug**
  (z. B. Fahrzeugalter-Klasse — aber **kein** Kennzeichen, **keine** VIN, **kein**
  Klarname, **keine** Freitexte). Rohantwort wird DSGVO-gefiltert abgelegt, konsistent
  mit sevDesk (`etl/autoixpert/project.ts`).

---

## 4. Schema (raw)

```
raw.autoixpert_gutachten (id text PK, aktenzeichen text, payload jsonb NOT NULL, extracted_at timestamptz NOT NULL)
```

`payload` bereits DSGVO-gefiltert (s. 3). `id` = autoiXpert-Gutachten-ID (Format
klären: numerisch oder Hash — daher `text` statt `bigint`). `aktenzeichen` vom
zugehörigen Deal mitgegeben. Migration `sql/009_raw_autoixpert.sql`.

---

## 5. core / marts

- **`core.fact_gutachten`** (View über raw; Grain: ein Gutachten je Aktenzeichen):
  `aktenzeichen`, `gutachten_id`, `wiederbeschaffungswert`, `restwert`,
  `wertminderung`, `reparaturkosten_brutto`/`_netto`, `nutzungsausfall_tagessatz`,
  `gutachtenart`, sowie abgeleitet `ist_totalschaden` (Reparatur > WBW) und
  `ueber_130_prozent`. Beträge brutto/netto klar benannt, keine Umrechnung.
- **marts:**
  - `v_bvsk_korridor` — Honorar (Σ `Grundhonorar` aus `fact_rechnungsposition`,
    Phase 3) vs. Schadenhöhe/WBW je Gutachten → BVSK-Einordnung (Leitfrage 8).
  - `v_totalschaden_quote` — Anteil Totalschaden / 130-%-Fälle je Zeitraum, später
    Korrelation mit Kürzungen (Leitfrage 10).

Migration `sql/010_core_autoixpert.sql`.

---

## 6. Golden / Verifikation

- Golden erweitern: für 1–2 bekannte Deals mit Gutachten-ID die Fachwerte (WBW,
  Restwert, Wertminderung) gegenprüfen. **Plausibilitäts-Checks:** WBW ≥ Restwert;
  `ist_totalschaden` == (Reparaturkosten > WBW); Werte ≥ 0.
- read-only, produktionssicher, analog `test:sevdesk` (+ Observability über
  `core._etl_run`).

---

## 7. Offene Fragen an den Inhaber

1. **Token/Inspektion:** read-only `AUTOIXPERT_API_TOKEN` als Coolify-Secret; für
   den korrekten/DSGVO-sicheren Bau **eine echte Gutachten-Antwort inspizieren**
   (Egress ist aus der Web-Session geblockt → Token + 1 Beispiel-Gutachten als JSON,
   PII geschwärzt, analog sevDesk-curl).
2. **API-Details:** Endpunkt für ein einzelnes Gutachten (`/Gutachten/<id>` als
   API oder nur Web-Deeplink?), Auth-Schema (Bearer vs. Header), Pagination,
   Feldnamen für WBW/Restwert/Wertminderung.
3. **Doppelquelle Reparaturkosten:** stehen in Pipedrive **und** autoiXpert —
   welche ist maßgeblich? (Vorschlag: autoiXpert als Fachquelle, Pipedrive als
   Fallback.)
4. **Totalschaden/130 %:** Definition bestätigen (brutto oder netto Reparaturkosten
   gegen WBW? Restwert-Berücksichtigung?).
5. **Gutachtenart-Feld** in autoiXpert: bestätigen, dass es die bestehende Dimension
   (Haftpflicht/Bewertung) nur spiegelt, nicht erweitert.

---

## 8. Reihenfolge / Checkliste

- [ ] autoiXpert-API final gegen Doku + echtes Gutachten verifizieren (Token/Sample)
- [ ] `AUTOIXPERT_API_TOKEN` als Coolify-Secret an der ETL-Ressource
- [ ] `sql/009_raw_autoixpert.sql` (raw-Tabelle)
- [ ] `etl/autoixpert/{client,project,extract-gutachten}.ts` (DSGVO-Filter Option A)
- [ ] `sql/010_core_autoixpert.sql` (fact_gutachten + marts)
- [ ] Golden erweitern + verifizieren
- [ ] `etl`-Deploy-Service um autoiXpert-Extraktion ergänzen (resiliente `;`-Kette)
