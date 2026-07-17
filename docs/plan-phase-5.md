# Plan Phase 5 — Kürzungsgrund / Durchsetzungsquote

Status: **Entwurf, zum Gegenlesen.** Noch nicht gebaut. Bei Datenmodellierung ist
der Plan die Arbeit — erst gegenlesen, dann bauen. Voraussetzung Phase 3 (sevDesk
positionsscharf) steht.

---

## 0. Ziel & Bezug zu den Leitfragen

Die **Durchsetzungsquote** ins Warehouse — laut CLAUDE.md „die wichtigste Zahl im
ganzen System". Sie misst, wie viel von dem, was ein Versicherer **kürzt**, der
Sachverständige per **Stellungnahme** wieder **durchsetzt**.

- **Leitfrage 2** — welcher Versicherer kürzt wie oft, mit welchem Betrag, aus
  welchem Grund?
- **Leitfrage 3** — welche Kürzungen setze ich per Stellungnahme durch — lohnt der
  Aufwand?
- **Leitfrage 5** — wo entstehen Zahlungsausfälle?
- **Leitfrage 10** — Korrelation Totalschaden/130-% mit Kürzungen.

---

## 1. Begriffsmodell — drei Größen, NIE vermischen

Aus CLAUDE.md, wörtlich verbindlich:

| Größe | Bedeutung | Quelle (heute) | Grain |
|---|---|---|---|
| **Forderung / Rechnung (Soll)** | Was der SV berechnet | `core.fact_rechnungsposition` (sevDesk) | Position |
| **Kürzung (Behauptung)** | Was der Versicherer *initial* nicht zahlen will | **offen — s. §2** | ? |
| **Ausbuchung (Ist-Verlust)** | Was am Ende *tatsächlich* verloren ist | `core.fact_ausbuchung` (Pipedrive) | Deal/Fall |

- **Durchsetzung = Kürzung − Ausbuchung** (was per Stellungnahme zurückgeholt wurde).
  **Durchsetzungsquote = 1 − (Σ Ausbuchung / Σ Kürzung).**
- **Ausbuchung ≠ Kürzung** — zwei getrennte Fakten. Die Kürzung ist die *Behauptung*
  des Versicherers, die Ausbuchung der *tatsächliche* Verlust nach Stellungnahme.
- **Haftungsquote/Teilschuld ist KEINE Kürzung.** Reguliert die Gegenseite nur zu
  50 %, hat der Versicherer *korrekt* reguliert. Eigene Kategorie, eigener View —
  landet Teilschuld im Kürzungstopf, sieht ein korrekter Versicherer schlecht aus
  und die Kennzahl ist wertlos. (`Ausgebucht Grund` 71 = Teilschuld → separat.)
- **Alle Beträge brutto.** `null ≠ 0` beim Ausbuchungsbetrag bleibt erhalten.

---

## 2. Der Engpass: Woher kommt die KÜRZUNG?

Die Ausbuchungsseite ist modelliert (`fact_ausbuchung`: `ausgebucht_betrag`,
`ausgebucht_grund`). Die **initiale Kürzung** ist die offene Quelle — und ohne sie
ist die Durchsetzungsquote nicht berechenbar. Befund der Feldrecherche:

- **In Pipedrive gibt es KEIN Kürzungs-Feld** (100+ Deals gescannt, s.
  `docs/field-mapping.json`). Nur Ausbuchung (Betrag + Grund).
- Es existiert kein n8n-Data-Table für Kürzungen.
- Es gibt einen n8n-Workflow **„Autoixpert Kürzungssync Pipedrive"** — Hinweis, dass
  Kürzungsdaten in **autoiXpert** entstehen (Stellungnahme-/`expert_statement`-Modul)
  und ggf. nach Pipedrive fließen (Ziel-Feld unklar; evtl. Note/Activity statt
  Custom Field).

**ENTSCHIEDEN (Inhaber, 2026-07-15): sevDesk-Differenz.** Die Kürzung wird aus der
sevDesk-Rechnung abgeleitet, mit einer präzisen Domänenregel:

> **Kürzung := `sumGross − paidAmount` (offener Betrag) je Rechnung.** Der offene
> Betrag IST immer die Kürzung — **außer** er entspricht (±5 ct) der **MwSt** der
> Rechnung. Dann hat der Versicherer nur die **USt einbehalten** (Geschädigter
> vorsteuerabzugsberechtigt) → **keine Kürzung.**

Zwingende Zusätze aus den Domänenregeln (CLAUDE.md), die über der Faustregel stehen:
- **Nur geschlossene Fälle** (`status = 'won'`). Bei offenen Fällen ist die Differenz
  nur „noch nicht bezahlt", keine Kürzung.
- **`null ≠ 0`:** ist `paidAmount` nicht erfasst (null), ist keine Kürzungsaussage
  möglich → `kuerzung_betrag = null` (nicht 0).
- **Teilschuld/Haftungsquote bleibt getrennt.** Fälle mit
  `ausgebucht_grund = Teilschuld (71)` gehören NICHT in den Kürzungstopf, auch wenn
  eine Differenz existiert — sonst sieht ein korrekt regulierender Versicherer
  schlecht aus. Markiert als `ist_haftungsquote`, in allen Kürzungs-Auswertungen
  ausgeschlossen. **(Diese Regel setze ich über die Inhaber-Faustregel „Differenzen
  sind immer Kürzungen" — bitte gegenlesen.)**

**Grain-Konsequenz:** `paidAmount` ist rechnungsscharf, nicht positionsscharf →
Kürzung entsteht **je Rechnung/Fall**, nicht je Position. „Welche Position wird
gekürzt" (LF2/LF3 positionsscharf) ist mit dieser Quelle NICHT beantwortbar; dafür
bräuchte es die autoiXpert-Stellungnahme (später).

**Verworfen:** (a) autoiXpert-Stellungnahme (Zugriff unklar, viele Werte nur im PDF),
(c) neues Pipedrive-Feld (Erfassungsaufwand).

---

## 3. Zwei Ausbaustufen (je nach §2)

**Szenario A — Kürzung wird strukturiert erfasst (Ziel):**
- `core.fact_kuerzung` (Grain: Position × Kürzungsereignis) mit Kürzungsbetrag,
  Kürzungsgrund, Versicherer, Aktenzeichen. Join zu `fact_rechnungsposition`
  (Soll je Position) und `fact_ausbuchung` (Ist-Verlust je Fall).
- Ergibt die **echte Durchsetzungsquote** je Versicherer/Grund/Position/Zeitraum.

**Szenario B — vorerst nur Ausbuchung (Interim, ohne neuen Zugang):**
- Kürzungsgrund-Analyse auf den **Ausbuchungs**-Daten: welcher Grund, wie oft,
  welcher Betrag — Teilschuld sauber getrennt. Liefert LF2/LF5 teilweise und die
  „was wird warum ausgebucht"-Sicht, **aber nicht** die Durchsetzungsquote (dafür
  fehlt die Kürzung). Definiert zugleich die Minimal-Erfassung für Szenario A.

---

## 4. Kürzungsgrund-Enum (Migration ausgebucht_grund → kürzungsgrund)

`Ausgebucht Grund` (Pipedrive-Enum) trägt heute: 69=Grundhonorar, 70=Nebenkosten,
**71=Teilschuld (Haftungsquote!)**, 73=Mangel an Beweisen, + „Ablehnung durch
Versicherung". `docs/field-mapping.json` vermerkt: „In Phase 5 auf das
Kürzungsgrund-Enum umzustellen (MENSCH)."

- `dim_kuerzungsgrund` datengetrieben (wie `dim_ausbuchungsgrund`), unkartierte
  Werte sichtbar.
- **Teilschuld → eigene Klasse „Haftungsquote", NICHT Kürzung.** Filter in jeder
  Durchsetzungs-Auswertung: `WHERE grund <> 'Haftungsquote'`.

---

## 5. Versicherer-Zuordnung (Voraussetzung LF2)

„Welcher Versicherer kürzt" braucht den **Versicherer je Fall**. `deal.org_id` ist
dünn befüllt (zentrale Lücke laut CLAUDE.md). **Phase-4-Fund nutzen:**
`autoixpert_gutachten.payload.insurance.organization_name` liefert den Versicherer
zuverlässig → als primäre Quelle für LF2 (Fallback `dim_organisation` über org_id),
sobald der Phase-4-Extraktor läuft.

---

## 6. core / marts (Szenario A)

- `core.fact_kuerzung` — Grain Position × Kürzung; brutto; Versicherer; Grund.
- `marts.v_durchsetzungsquote` — 1 − Σ Ausbuchung / Σ Kürzung, je Versicherer /
  Grund / Zeitraum (Haftungsquote ausgeschlossen).
- `marts.v_kuerzung_je_position` — welche Position wird wie oft / wie stark gekürzt
  (LF2/LF3).
- `marts.v_stellungnahme_roi` — durchgesetzter Betrag vs. Aufwand (LF3: lohnt sich?).
- `marts.v_haftungsquote` — Teilschuld-Fälle getrennt (Kontrolle, nicht Kürzung).

Migration **`sql/010_core_kuerzung.sql` — GEBAUT & lokal verifiziert** (Views über
raw/core, kein Transform-Schritt). Phase-4-Core rückt auf `sql/011`.

**Verifikation (lokales Postgres, gezielte Testfälle):** MwSt-Einbehalt (offen ≈
Steuer → keine Kürzung), Haftungsquote/Teilschuld (grund 71 → 0, getrennt), nur
`status='won'`, `paidAmount` null → `kuerzung_betrag` null (null≠0) — alle korrekt.

---

## 7. DSGVO

Unverändert Option A: keine Freitexte (Kürzungs-/Stellungnahme-Begründungstexte
enthalten oft Personenbezug → **nicht** übernehmen; nur Grund-Enum + Betrag).
Versicherer/Werkstatt/Anwalt als juristische Personen im Klartext erlaubt.

---

## 8. Offene Fragen an den Inhaber

- ~~Kürzungsquelle~~ — **ENTSCHIEDEN: sevDesk-Differenz** (§2), gebaut & verifiziert.
- ~~Grain~~ — folgt aus der Quelle: **je Rechnung/Fall** (paidAmount ist nicht
  positionsscharf). Positionsscharfe Kürzung („welche Position") bleibt offen.

**GELÖST (Inhaber, 2026-07-15): Ausbuchung aus dem sevDesk-Beleg.** Je Ausbuchung
erstellt das Büro einen sevDesk-Beleg (Voucher) „Forderungsverlust <Aktenzeichen>";
dessen Betrag ist die tatsächliche Ausbuchung — eine EIGENE, vollständige Quelle
(unabhängig von der Kürzung und vollständiger als die dünne Pipedrive-
`ausgebucht_betrag`). Damit wird die Durchsetzungsquote echt messbar:

> **Kürzung** = `sumGross − paidAmount` je Rechnung (fact_kuerzung).
> **Ausbuchung** = Σ Forderungsverlust-Beleg je Fall (fact_forderungsverlust).
> **Durchsetzungsquote = 1 − Σ Ausbuchung / Σ Kürzung.** Kein Beleg = nichts
> abgeschrieben = voll durchgesetzt.

Gebaut & lokal verifiziert (`sql/012` raw, `sql/013` core+marts, `extract-vouchers.ts`):
an Testfällen ergibt sich eine plausible Quote (z. B. Kürzung 200 / Ausbuchung 40 →
80 % durchgesetzt), Teilschuld korrekt ausgeschlossen. `v_durchsetzung_diagnose`
stellt je Fall Rechnungsdifferenz, Pipedrive- und Beleg-Ausbuchung nebeneinander.

**Noch offen:**
1. **Betragsfeld des Belegs:** `sumGross` (brutto, aktueller Default) oder `sumNet`
   der maßgebliche Ausbuchungsbetrag? An einem echten Forderungsverlust-Beleg zu
   bestätigen.
2. **An Prod-Daten prüfen (Metabase):** `v_durchsetzung_diagnose` — laufen Kürzung
   und Beleg-Ausbuchung wie erwartet auseinander? Coverage des Aktenzeichen-Joins?
3. **Kürzungsgrund-Enum:** `Ausgebucht Grund` in `Kürzungsgrund` umbenennen/aufteilen?
4. **Versicherer je Fall:** autoiXpert (Phase 4) als primäre Quelle für LF2 freigeben?
5. **USt-Einbehalt:** ±5 ct bestätigt? Rechnung mit *gleichzeitig* USt-Einbehalt UND
   Kürzung (heute als reine Kürzung gewertet)?

---

## 9. Reihenfolge / Checkliste

- [x] Kürzungsquelle mit Inhaber geklärt (§2): sevDesk-Differenz + USt-Regel
- [x] `core.fact_kuerzung` gebaut (`sql/010`), Grain je Rechnung/Fall, Teilschuld
      getrennt, USt-Einbehalt-Ausnahme, nur `won`, null≠0
- [x] marts `v_kuerzung_je_versicherer` (LF2), `v_kuerzung_je_grund`,
      `v_kuerzung_monat`
- [x] **Ausbuchung aus sevDesk-Beleg** (`sql/012` raw + `extract-vouchers.ts` +
      `sql/013` `core.fact_forderungsverlust`): Durchsetzungsquote messbar
- [x] `marts.v_durchsetzung` (LF3, Kürzung vs. Beleg-Ausbuchung) +
      `v_durchsetzung_diagnose`
- [x] Logik lokal an gezielten Testfällen verifiziert (inkl. echter Durchsetzung)
- [ ] **Betragsfeld bestätigen** (Beleg `sumGross` vs. `sumNet`) an echtem Sample
- [ ] `extract:vouchers` in die Deploy-Kette (`docker-compose`), dann an Prod-Daten
      prüfen (Metabase: `v_durchsetzung_diagnose`)
- [ ] Kürzungsgrund-Enum final; Versicherer-Join autoiXpert (Phase 4)
- [ ] Metabase-Dashboards (Phase 7)
