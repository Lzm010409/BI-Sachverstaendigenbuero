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

**Verifiziert an zwei echten Samples** (`807KwgxI7Xez` state=recorded;
`PGCYRWGAx0XX` state=**done**, completion_date gesetzt):

1. **Die numerischen Fachwerte stehen NICHT in der externalApi — auch nicht im
   fertigen Gutachten.** Vom Inhaber bestätigt: WBW, Restwert, Wertminderung und
   Reparaturkosten existieren **nur in den generierten PDFs**. Das Report-Objekt
   trägt sie in keinem Zustand. `project.ts::fachwerte()` liefert sie daher bewusst
   als `null` mit `_quelle_pdf_only:true`. **→ Wie die Zahlen ins Warehouse kommen,
   ist eine offene Architekturfrage (s. §7): PDF-Parsing vs. Pipedrive-
   Reparaturkosten vs. evtl. separater Valuation-Endpunkt.**
2. **Dokument-Präsenz als Fachsignal** (DSGVO-sicher, nur `type`, keine URLs/Titel):
   `documents[]` verrät strukturiert, welche Kalkulationen existieren —
   `dat_market_analysis` (WBW), `custom_residual_value_bid_list` (Restwert),
   `diminished_value_protocol` (Wertminderung), `dat_damage_calculation`
   (Reparatur). `project.ts::dokumente()` führt Bool-Flags. Signal für Leitfrage 10
   (Bewertung/Restwert erstellt = Totalschaden-Indiz), auch ohne die Zahl selbst.
3. **Bonus Leitfrage 2:** `insurance.organization_name` (z. B. „WGV-Versicherung AG",
   „HUK-COBURG …") liegt sauber vor — schließt die in Pipedrive nur dünn befüllte
   Versicherer-Lücke. `type` (liability → Haftpflicht; bestätigt Q5). `token` **ist**
   das Aktenzeichen → Join + Kreuzvalidierung.

**DSGVO-Entscheidungen (in project.ts umgesetzt, gegen beide Samples verifiziert —
kein Leak):**
- `insurance`/`lawyer`/`garage` → `organization_name` + pseudonyme `contact_id`.
  Einzelanwalt/-werkstatt kann Personennamen tragen (z. B. „Rechtsanwalt Philipp
  Nadler"); nach CLAUDE.md sind Anwaltskanzleien/Werkstätten juristische Personen,
  Klartext erlaubt.
- **`intermediary` (Vermittler/Auftragsquelle) → NUR `contact_id`, KEIN Klartext-
  Name.** Grund: nicht von der Klartext-Erlaubnis gedeckt und demonstrativ eine
  natürliche Person (in einem echten Sample trug `organization_name` einen
  Personennamen statt einer Firma). Pseudonym erlaubt Gruppierung je Quelle
  (Leitfrage 4) ohne Personenbezug. **Offene Frage:** Braucht LF4 doch den
  Klarnamen der Quelle?
- Geschädigter (`claimant`), VIN, alle Kennzeichen, Freitexte, Anschriften, Foto-
  Beschreibungen, Session-URLs → vollständig verworfen.

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

Migration `sql/011_core_autoixpert.sql`.

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
- ~~Q2 API-Details~~ — `GET /externalApi/v1/reports/{id}`, **Bearer**, kein Paging.
- ~~Q5 Gutachtenart~~ — `type` spiegelt die Dimension (liability = Haftpflicht).
- ~~Fertiges Gutachten~~ — geliefert (`PGCYRWGAx0XX`). Ergebnis: **Fachwerte sind
  nicht in der API, nur im PDF.** `AUTOIXPERT_API_TOKEN` ist gesetzt.

**Die zentrale offene ARCHITEKTURFRAGE (blockiert Leitfragen 8 & 10):**
Woher kommen **WBW, Restwert, Wertminderung** (numerisch)? Sie stehen nur im PDF.
Optionen:
- **(A) Vorerst ohne die Zahlen bauen:** Metadaten + Versicherer (LF2) + Dokument-
  Signal (welche Kalkulation existiert) jetzt liefern; numerische Fachwerte später.
  Schnell, DSGVO-sicher, aber LF8/LF10 bleiben unvollständig.
- **(B) PDF-Parsing** der DAT-Dokumente (`dat_market_analysis` → WBW,
  `dat_damage_calculation` → Reparatur, …). Mächtig, aber aufwändig/brüchig; braucht
  Regeln je DAT-Layout. Läuft nur im Container (PDF-Download via externalApi).
- **(C) Separater Valuation-Endpunkt?** Ggf. bietet die externalApi eine
  Bewertungs-/Kalkulations-Ressource jenseits von `/reports/{id}`. **Aus der Session
  nicht prüfbar (Egress geblockt, auch Doku).** Bitte in der autoiXpert-Doku
  (`dev.autoixpert.de`) prüfen: gibt es z. B. `…/reports/{id}/valuation` o. Ä.?
- **(D) Aus Pipedrive:** Reparaturkosten liegen dort strukturiert vor (`REPARATUR-
  KOSTEN_BRUTTO/_NETTO`). WBW/Restwert/Wertminderung dort NICHT — es sei denn, sie
  werden künftig erfasst.

**Weitere offene Fragen:**
1. **Reparaturkosten-Quelle:** Da autoiXpert die Zahl nicht per API liefert, ist
   Pipedrive `REPARATURKOSTEN_BRUTTO` die einzige strukturierte Quelle. Ist dieses
   Feld für (nahezu) alle Gutachten zuverlässig gefüllt, und ist **brutto** die
   maßgebliche Größe für die BVSK-Schadenhöhe (LF8)?
2. **Totalschaden/130 %:** Definition bestätigen (brutto/netto Reparaturkosten gegen
   WBW? Restwert-Berücksichtigung?) — relevant, sobald WBW verfügbar ist.
3. **Vermittler (LF4):** Reicht die pseudonyme `contact_id` je Auftragsquelle, oder
   wird der Klarname der Quelle gebraucht (dann DSGVO-Abwägung nötig)?

---

## 8. Reihenfolge / Checkliste

- [x] autoiXpert-API-Endpunkt + Auth verifiziert (Live-n8n; gegen 2 echte Samples)
- [x] `sql/009_raw_autoixpert.sql` (raw-Tabelle)
- [x] `etl/autoixpert/{client,project,extract-gutachten,run-log}.ts` — DSGVO-Filter
      Option A, gegen recorded- UND done-Sample verifiziert (kein Leak)
- [x] Befund: numerische Fachwerte nur im PDF (nicht in der API); Dokument-Signal
      + Versicherer (LF2) strukturiert verfügbar
- [x] `AUTOIXPERT_API_TOKEN` gesetzt (Coolify-Secret, Bearer)
- [ ] **ENTSCHEIDUNG Fachwert-Quelle** (§7 A–D) — Voraussetzung für LF8/LF10
- [ ] `extract:gutachten` in die Deploy-Kette (docker-compose) — erst nach Gegenlesen
- [ ] `sql/011_core_autoixpert.sql` (`core.fact_gutachten` + `v_versicherer_je_fall`
      für LF2; `v_bvsk_korridor`/`v_totalschaden_quote` sobald Fachwerte fließen)
- [ ] Golden erweitern (DSGVO-redigiertes Fixture) + verifizieren
