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

**Kandidaten-Quellen (Inhaber entscheidet):**
- **(a) autoiXpert Stellungnahme / `expert_statement`** — fachlich die richtige
  Quelle: die Kürzung wird je Position beim Erstellen der Stellungnahme erfasst.
  Zugriff derzeit unklar (Phase-4-Befund: viele Fachwerte nur im PDF; Egress
  geblockt). Zu prüfen, ob die externalApi Stellungnahme-/Kürzungs-Positionen
  strukturiert liefert.
- **(b) sevDesk `sumGross − paidAmount`** — die Differenz aus berechnet vs. bezahlt.
  Enthält aber ALLES (Kürzung + Teilschuld + noch-nicht-bezahlt) und ist kein
  „initialer Kürzungsbetrag" → nur grobe Näherung, vermischt Größen. Nicht sauber.
- **(c) Manuelle/prozessuale Erfassung** — ein neues Pipedrive-Feld „Kürzungsbetrag"
  (+ Grund, + Stellungnahme-Erfolg) analog zum Ausbuchungsfeld, das der Inhaber im
  Prozess füllt. Sauber, aber Erfassungsaufwand.

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

Migration `sql/010_*` (Nummer prüfen — Phase 4 reserviert `sql/010` noch nicht
gebaut; ggf. `sql/011`). Idempotent, Views über raw/core, kein Transform-Schritt.

---

## 7. DSGVO

Unverändert Option A: keine Freitexte (Kürzungs-/Stellungnahme-Begründungstexte
enthalten oft Personenbezug → **nicht** übernehmen; nur Grund-Enum + Betrag).
Versicherer/Werkstatt/Anwalt als juristische Personen im Klartext erlaubt.

---

## 8. Offene Fragen an den Inhaber

1. **Kürzungsquelle (§2) — die Kernfrage:** Wo wird die *initiale* Kürzung erfasst?
   autoiXpert-Stellungnahme (strukturiert abrufbar?), sevDesk-Differenz (unsauber),
   oder soll ein neues Pipedrive-Feld „Kürzungsbetrag" den Prozess erfassen?
2. **Grain:** Kürzung je **Position** (ideal für „welche Position wird gekürzt") oder
   nur je **Fall/Rechnung** (gröber, aber einfacher)?
3. **Kürzungsgrund-Enum:** `Ausgebucht Grund` umbenennen/aufteilen? Finale Werteliste
   (inkl. sauberer Trennung Teilschuld/Haftungsquote)?
4. **Stellungnahme-Erfolg:** Gibt es ein Signal/Feld, ob eine Stellungnahme
   erfolgreich war (durchgesetzt ja/nein bzw. Betrag)? Nötig für LF3-ROI.
5. **Versicherer je Fall:** autoiXpert (Phase 4) als primäre Quelle für LF2
   freigeben?

---

## 9. Reihenfolge / Checkliste

- [ ] Kürzungsquelle mit Inhaber klären (§2/§8.1) — blockiert Szenario A
- [ ] Kürzungsgrund-Enum final (§4/§8.3)
- [ ] `fact_kuerzung` modellieren (Grain je Antwort auf §8.2)
- [ ] marts: `v_durchsetzungsquote`, `v_kuerzung_je_position`, `v_stellungnahme_roi`,
      `v_haftungsquote`
- [ ] Versicherer-Join (autoiXpert/Phase 4 oder org_id) verdrahten
- [ ] Golden/Plausibilität: Σ Ausbuchung ≤ Σ Kürzung; Haftungsquote nie im
      Kürzungstopf; Durchsetzungsquote ∈ [0,1]
- [ ] Metabase-Dashboards (Phase 7)
