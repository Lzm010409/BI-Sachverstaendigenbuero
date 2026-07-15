# Plan Phase 4 — autoiXpert (Fachdaten: WBW, Restwert, Wertminderung …)

Status: **Teilweise gebaut (Unterbau steht, verifiziert).** Bei Datenmodellierung
ist der Plan die Arbeit — erst gegenlesen, dann bauen.

---

## Stand 2026-07-15 — verifiziert & gebaut

**API bestätigt (aus Live-n8n „autoiXpert DAT-Kalkulation Download", nicht aus dem
Gedächtnis):**
- Einzel-Gutachten: `GET https://app.autoixpert.de/externalApi/v1/reports/{id}`,
  Auth **Bearer** (`httpBearerAuth`). Antwort in `{ report: {...} }` gewrappt.
- Egress zu `*.autoixpert.de` (App **und** Doku `dev.autoixpert.de`) ist aus der
  Web-Session per Netzwerk-Policy geblockt → Extraktion läuft nur im Coolify-`etl`-
  Container. Verifikation der Struktur erfolgte über ein vom Inhaber geliefertes
  echtes Report-JSON.

**Gebaut (typecheck grün, DSGVO-Filter gegen echtes Sample verifiziert):**
- `sql/009_raw_autoixpert.sql` — `raw.autoixpert_gutachten` (DSGVO-gefiltertes payload).
- `etl/autoixpert/client.ts` — Bearer-Client `fetchReport(id)` (404 → null).
- `etl/autoixpert/project.ts` — DSGVO deny-by-default Whitelist (s. u.).
- `etl/autoixpert/extract-gutachten.ts` — iteriert Deals mit Gutachten-ID, fetch +
  upsert; **Sicherheitsgate:** ohne `AUTOIXPERT_API_TOKEN` No-op (exit 0).
- npm-Script `extract:gutachten`. **Noch NICHT** in der Deploy-Kette (docker-compose)
  verdrahtet — erst nach Fachwert-Verifikation + Gegenlesen.

**Zwei zentrale Befunde aus dem echten Sample (report `807KwgxI7Xez`, state=recorded):**
1. **Fachwerte fehlen im aufgenommenen Zustand.** WBW/Restwert/Wertminderung/
   Reparaturkosten/Nutzungsausfall sind bei `state=recorded`, `completion_date=null`
   NICHT im Report enthalten — sie entstehen erst im fertigen Gutachten bzw. in der
   DAT-Kalkulation (separates Dokument). **→ Es fehlt noch genau eine Sache: ein
   FERTIGES Gutachten (completion_date gesetzt) als JSON, um die Fachwert-Feldnamen
   zu bestätigen.** Bis dahin liest `project.ts::fachwerte()` defensiv über plausible
   Kandidaten-Pfade (numerisch gecoerct) und markiert `_fachwerte_verifiziert:false`.
2. **Bonus für Leitfrage 2:** `insurance.organization_name` (z. B. „WGV-Versicherung
   AG") liegt sauber vor — genau die in Pipedrive nur dünn befüllte Versicherer-
   Zuordnung. autoiXpert kann diese Lücke schließen. Ebenso `intermediary.
   organization_name` (Auftragsquelle, z. B. „INTERNET" → Leitfrage 4) und
   `type` (liability → Haftpflicht; bestätigt Q5). `token` **ist** das Aktenzeichen
   (MMJJ/NummerTG) → Join + Kreuzvalidierung gegen den Deal.

**DSGVO-Hinweis (zur Kenntnis):** `lawyer`/`garage`/`insurance` werden auf
`organization_name` + pseudonyme `contact_id` reduziert. Bei Einzelanwälten/-werk-
stätten kann `organization_name` einen Personennamen tragen (z. B. „Rechtsanwältin
Claudia Busch"). Nach CLAUDE.md sind Anwaltskanzleien/Werkstätten juristische
Personen und im Klartext erlaubt; der geschützte Geschädigte (`claimant`) wird
vollständig verworfen.

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

**Erledigt (2026-07-15):**
- ~~Q2 API-Details~~ — Endpunkt `GET /externalApi/v1/reports/{id}`, **Bearer**,
  keine Pagination (Einzelabruf je ID). Aus Live-n8n + echtem Sample bestätigt.
- ~~Q5 Gutachtenart~~ — `type` spiegelt die bestehende Dimension (Sample:
  `liability` = Haftpflicht; `valuation` = Bewertung erwartet). Keine neue Art.

**Noch offen — genau das blockiert den Fachwert-Teil (Leitfragen 8 & 10):**
1. **Ein FERTIGES Gutachten als JSON** (`completion_date` gesetzt, PII wie gehabt
   unkritisch — die Whitelist filtert ohnehin). Nur so lassen sich die Feldnamen
   für **WBW, Restwert, Wertminderung, Reparaturkosten (netto/brutto),
   Nutzungsausfall-Tagessatz** bestätigen — im aufgenommenen Zustand fehlen sie.
   Frage dazu: Stehen diese Werte als **strukturierte Felder** im Report, oder nur
   im DAT-Kalkulations-**Dokument** (PDF)?
2. **`AUTOIXPERT_API_TOKEN`** als Coolify-Secret an der ETL-Ressource (read-only,
   Bearer). Erst dann läuft der (bereits gebaute, gegatete) Extraktor produktiv.
3. **Doppelquelle Reparaturkosten:** stehen in Pipedrive **und** autoiXpert —
   welche ist maßgeblich? (Vorschlag: autoiXpert als Fachquelle, Pipedrive als
   Fallback.)
4. **Totalschaden/130 %:** Definition bestätigen (brutto oder netto Reparaturkosten
   gegen WBW? Restwert-Berücksichtigung?).

---

## 8. Reihenfolge / Checkliste

- [x] autoiXpert-API-Endpunkt + Auth verifiziert (Live-n8n; Struktur gegen echtes Sample)
- [x] `sql/009_raw_autoixpert.sql` (raw-Tabelle)
- [x] `etl/autoixpert/{client,project,extract-gutachten,run-log}.ts` (DSGVO-Filter Option A, verifiziert)
- [ ] **FERTIGES Gutachten (completion_date gesetzt) als JSON** → Fachwert-Feldnamen
      bestätigen, `project.ts::fachwerte()` finalisieren, `_fachwerte_verifiziert:true`
- [ ] `AUTOIXPERT_API_TOKEN` als Coolify-Secret an der ETL-Ressource (Bearer)
- [ ] `sql/010_core_autoixpert.sql` (`core.fact_gutachten` + marts `v_bvsk_korridor`,
      `v_totalschaden_quote`; zusätzlich Versicherer je Fall → Leitfrage 2)
- [ ] Golden erweitern (DSGVO-redigiertes Fixture) + verifizieren
- [ ] `etl`-Deploy-Service um `extract:gutachten` ergänzen (resiliente `;`-Kette),
      erst nach Fachwert-Verifikation + Gegenlesen
