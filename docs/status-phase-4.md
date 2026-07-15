# STATUS Phase 4 — autoiXpert (Fachdaten)

Dedizierter Handoff für Phase 4. **Phase 4 ist bewusst PAUSIERT** (Stand 2026-07-15):
Der Unterbau steht und ist verifiziert, aber die numerischen Fachwerte hängen an
einer offenen Entscheidung des Inhabers (PDF-Verarbeitung). Zuerst diese Datei +
`docs/plan-phase-4.md` lesen.

---

## Warum pausiert

Ziel von Phase 4 sind **WBW, Restwert, Wertminderung, Reparaturkosten** →
Leitfragen 8 (BVSK-Korridor) & 10 (Totalschaden-/130-%-Quote). An zwei echten
Gutachten (state `recorded` und state `done`) verifiziert und vom Inhaber
bestätigt: **Diese Zahlen stehen NICHT strukturiert in der autoiXpert-externalApi —
nur in den generierten PDFs.** Wie die Zahlen ins Warehouse kommen (PDF-Parsing vs.
evtl. Valuation-Endpunkt vs. Pipedrive-Reparaturkosten), klärt der Inhaber separat.
Bis dahin ruht der Fachwert-Teil.

## Was steht (gebaut, verifiziert, gepusht — NICHT in der Deploy-Kette)

Branch `claude/status-md-next-step-blbeam`. Typecheck grün. DSGVO-Filter gegen
BEIDE Samples geprüft — **kein PII-Leak**.

- `sql/009_raw_autoixpert.sql` — `raw.autoixpert_gutachten` (id, aktenzeichen,
  DSGVO-gefiltertes payload, extracted_at).
- `etl/autoixpert/client.ts` — Bearer-Client `fetchReport(id)` (404 → null).
  Endpunkt aus Live-n8n verifiziert: `GET …/externalApi/v1/reports/{id}`.
- `etl/autoixpert/project.ts` — DSGVO deny-by-default Whitelist (s. u.).
- `etl/autoixpert/extract-gutachten.ts` — iteriert Pipedrive-Deals mit gesetzter
  `DEAL_FIELDS.AUTOIXPERT_GUTACHTEN_ID`, holt je ID ein Gutachten, upsert.
  **Sicherheitsgate:** ohne `AUTOIXPERT_API_TOKEN` No-op (exit 0).
- `etl/autoixpert/run-log.ts` — Observability (core._etl_run).
- npm-Script `extract:gutachten`.

`AUTOIXPERT_API_TOKEN` ist als Coolify-Secret gesetzt.

## Verifizierte Fakten (nicht aus dem Gedächtnis)

- API: `GET https://app.autoixpert.de/externalApi/v1/reports/{id}`, **Bearer**,
  kein Paging (Einzelabruf). Antwort in `{ report: {…} }` gewrappt.
- Egress zu `*.autoixpert.de` (App **und** Doku `dev.autoixpert.de`) ist aus der
  Web-Session per Netzwerk-Policy geblockt → Extraktion nur im Coolify-`etl`-
  Container; Struktur-Verifikation über vom Inhaber gelieferte JSON-Samples.
- `token` **ist** das Aktenzeichen (MMJJ/NummerTG) → Join + Kreuzvalidierung.
- `type`: `liability` = Haftpflicht (`valuation` = Bewertung erwartet). Keine neue
  Auftragsart (bestätigt Q5).

## Sofort verwertbar OHNE die PDF-Zahlen

- **Leitfrage 2 (Versicherer je Fall):** `insurance.organization_name` (z. B.
  „WGV-Versicherung AG", „HUK-COBURG …") liegt sauber vor — schließt die in
  Pipedrive nur dünn befüllte Versicherer-Lücke. `core`-View `v_versicherer_je_fall`
  ist damit baubar, sobald der Extraktor gelaufen ist.
- **Dokument-Signal (LF10-Indiz):** `project.ts::dokumente()` führt Bool-Flags
  `hat_dat_marktanalyse` (WBW erstellt), `hat_restwertgebote` (Restwert),
  `hat_minderwertprotokoll` (Wertminderung), `hat_dat_kalkulation` (Reparatur) —
  aus der bloßen Existenz der PDFs, DSGVO-sicher (nur `type`, keine URLs/Titel).

## DSGVO-Entscheidungen (umgesetzt, verifiziert)

- Whitelist deny-by-default: nur explizit benannte, personenbezugsfreie Felder.
- `insurance`/`lawyer`/`garage` → `organization_name` + pseudonyme `contact_id`
  (juristische Personen, Klartext nach CLAUDE.md erlaubt — auch Einzelanwalt).
- **`intermediary` (Vermittler) → NUR `contact_id`, kein Klartext-Name** (kann
  natürliche Person sein; nicht von der Klartext-Erlaubnis gedeckt). Gruppierung je
  Quelle für LF4 bleibt über den Pseudonym-Schlüssel möglich.
- Verworfen: Geschädigter, VIN, alle Kennzeichen, Freitexte (Schaden/Unfall/Vor-
  schaden), Anschriften, Foto-Beschreibungen, Session-URLs, Vertrags-/Vers.-Nummern.

## Offene Punkte (Inhaber)

1. **Entscheidung Fachwert-Quelle** (Plan §7 A–D) — der eigentliche Blocker für
   LF8/LF10. Inhaber prüft PDF-Verarbeitung.
2. **Reparaturkosten:** Pipedrive `Reparaturkosten brutto` ist die einzige
   strukturierte Quelle — zuverlässig gefüllt? Brutto = maßgebliche BVSK-Schadenhöhe?
3. **Vermittler (LF4):** reicht der Pseudonym-Schlüssel, oder braucht es den
   Klarnamen der Quelle (dann DSGVO-Abwägung)?

## Wiederaufnahme (wenn PDF-Frage geklärt)

1. Fachwert-Quelle je Entscheidung implementieren (`project.ts::fachwerte()` bzw.
   separater PDF-/Endpunkt-Extraktor).
2. `sql/010_core_autoixpert.sql`: `core.fact_gutachten` (+ `v_versicherer_je_fall`
   für LF2 schon jetzt; `v_bvsk_korridor`/`v_totalschaden_quote` sobald Zahlen fließen).
3. Golden erweitern (DSGVO-redigiertes Fixture) + verifizieren.
4. `extract:gutachten` in die `docker-compose`-Deploy-Kette (resiliente `;`-Kette),
   erst nach Gegenlesen.
