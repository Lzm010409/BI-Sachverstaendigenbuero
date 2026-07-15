# Feldmapping — Recon-Findings & offene Entscheidungen (Phase 0)

**Stand:** 2026-07-15
**Quelle:** Live-Stichproben über die Pipedrive-MCP-Schnittstelle
(`getDeals`/`getOrganizations`/`getStages` mit `include_option_labels=true` und
`include_labels=true`). **Kein** Zugriff auf den Feldmetadaten-Endpunkt — dafür
fehlt noch der read-only Token. Diese Datei ist der Gegenlese-Gegenstand für die
🧑-MENSCH-Punkte aus Phase 0.

> Dieses Dokument ist von Hand gepflegt und wird **nicht** von
> `fetch-field-mapping.ts` überschrieben (anders als `field-mapping.json/.md`).

---

## 1. Was gegenüber dem vermuteten Mapping bestätigt / korrigiert wurde

Belegt aus den Werten (`status: confirmed` in `field-mapping.json`):

- **Ausgebucht Betrag / Grund**, **enthaltene MwSt** (= Netto·0,19),
  **Reparaturkosten brutto/netto** (Verhältnis exakt 1,19),
  **Hersteller/Modell/Kennzeichen**, **Erstzulassung**, **Fahrzeugalter-Klasse**,
  **Schadenbereich**, **Unfallhergang**, **sevDesk-Rechnungs-ID/Deeplink** — alle
  wie vermutet.
- **Kennzeichen**, **Unfallhergang**, **Vor-/Altschaden-Beschreibung** enthalten
  echten Personenbezug → in `field-mapping.json` als `dwh: exclude` markiert und
  in `fields.generated.ts` in `DWH_EXCLUDED_KEYS`.

## 2. Neue Felder, die im Auftrags-Mapping fehlten

| Key | Befund | Bedeutung fürs DWH |
|---|---|---|
| `f6970a4f…` | **autoiXpert-Gutachten-ID** (z. B. `fo0QXjtbEm4R`) | **Join-Key zu autoiXpert liegt bereits in Pipedrive!** Entschärft Phase 4 erheblich. |
| `102c6f8c…` | **autoiXpert-Deeplink** (`app.autoixpert.de/Gutachten/<id>`) | Beleg für die Gutachten-ID. |
| `7f32b816…` | **Nettobetrag** = `deal_value / 1,19` (belegt: 4526,36 = 5386,37/1,19) | Konsistenz-Check gegen enthaltene MwSt. |
| `62a4930b…` | **Datumsfeld**, Wert nahe `won_time` (2026-06-24) | Bedeutung offen (Besichtigung? Rechnung?), siehe ❓. |

## 3. Offene ❓ — brauchen Token **oder** deine Entscheidung

| Feld / Frage | Aktuelle Hypothese | Wie zu klären |
|---|---|---|
| `215832fc…` (Zahl 128/145/198) | **Nutzungsausfall-Tagessatz** (€/Tag) | Label aus Fields-API v2 (Token) bestätigt es sofort. |
| `4476af41…` (Zahl 2/4/14/17) | **Nutzungsausfall-Tage** | dito. Zusammen ergäbe das Nutzungsausfall gesamt. |
| `efd97e60…` vs `3bc5c0f3…` (beide Ja/Nein) | `efd97e60…` = **Vorschaden**, `3bc5c0f3…` = **Altschaden** (nach Feldreihenfolge + Freitextinhalt „nachlackiert" vs. Liste von Dellen) | Token bestätigt Labels. **MENSCH: bitte bestätigen.** |
| `cff1b2f6…` (Datum) | **Schadendatum** (liegt vor Anlage, nach Erstzulassung) | Token + dein Wissen: Erwerb? Anmeldung? Schaden? |
| `62a4930b…` (Datum, NEU) | Besichtigungs- oder Rechnungsdatum | Token + dein Wissen. |
| `621afa76…`, `b189ecbd…` (Deal, immer null) | unbekannt | Token. |
| Org-Custom-Fields `f8457fc2…` etc. (immer null) | unbekannt | Token. |

## 4. `org_id` — die zentrale Lücke (🧑 MENSCH-Entscheidung)

**Befund:**
- Organisationen sind über `org.label_ids` typisiert:
  - **35 = Versicherer** (HUK Coburg, Ergo, Provinzial, Cosmos Direkt, Verti,
    Fahrlehrer-Vers., Stadtwerke Neuss …)
  - **32 = Auftraggeber / Anwalt / Privat** (Kanzleien wie Buscher & Schmieszek,
    RA Wagner; Privatpersonen; „EIGEN")
- Auf dem **Deal** referenziert `org_id` — wenn gesetzt — den **Versicherer**
  (Deal 598 und 986 → HUK Coburg).
- **Aber `org_id` ist dünn befüllt.** In der Stichprobe hatten nur ~1/3 der Deals
  eine `org_id`. Ohne Versicherer-Zuordnung ist **Leitfrage 2 (Kürzung je
  Versicherer)** nicht flächendeckend berechenbar.

**Konsequenz / Entscheidung nötig (blockiert Phase 2):**
- a) Wird `org_id` künftig konsequent mit dem **Anspruchsgegner-Versicherer**
  gepflegt? (Prozess-Entscheidung, ggf. Pflichtfeld/Automatik.)
- b) Für die Historie: Versicherer kann in Phase 5 aus dem Abrechnungsschreiben
  gewonnen und je Aktenzeichen nachgetragen werden — das ist aber Phase 5.
- c) Bis dahin: `v_ausbuchung_monat` je Organisation nur für Deals mit gesetzter
  `org_id`; fehlende explizit als „ohne Versicherer-Zuordnung" ausweisen, **nicht**
  wegcoalescen.

## 5. `label_ids` entschlüsselt (🧑 MENSCH: 60 offen)

Deal-Labels sind **zwei Dinge in einem Feld**:

| ID | Bedeutung | Gruppe |
|---|---|---|
| 28 | **Haftpflichtgutachten** | Gutachtenart |
| 36 | **BEWERTUNG** (Wertermittlung) | Gutachtenart |
| 60 | **noch nicht beobachtet** ❓ | vermutlich weitere Gutachtenart |
| 61 | Neuer Fall | Fall-Alterung |
| 62 | Mittelalter Fall | Fall-Alterung |
| 63 | Überfälliger Fall | Fall-Alterung |

**Wichtig:** Die **Gutachtenart** (Leitfragen 1, 6, 10) steckt in `label_ids`,
nicht in einem Custom Field. Der ETL muss die Gutachtenart aus den Labels der
Gruppe {28, 36, 60, …} ableiten und die Alterungs-Flags {61,62,63} ignorieren.

- **MENSCH:** Was ist Label **60**? Gibt es weitere Gutachtenart-Labels
  (Kaskogutachten, Kurzgutachten, Reparaturbestätigung, Leasingrückläufer,
  Beweissicherung …)? Das ist zugleich der in Phase 4 gewünschte Katalog der
  Gutachtenarten.
- Org-Labels: **32/35** wie oben — bitte bestätigen; gibt es weitere (z. B. für
  Werkstätten)?

---

## 6. Offene 🧑-MENSCH-Punkte aus Phase 0 (Checkliste)

- [ ] **Pipedrive read-only Token** bereitstellen (+ Company-Domain) → dann
      `npm run fetch:fields` für das autoritative Mapping.
- [ ] Hypothesen in Abschnitt 3 bestätigen/korrigieren (Nutzungsausfall,
      Vor-/Altschaden-Zuordnung, Datumsfelder).
- [ ] `org_id`-Bedeutung/Prozess klären (Abschnitt 4) — **blockiert Phase 2**.
- [ ] Label 60 und den Gutachtenart-Katalog klären (Abschnitt 5).

Nach Klärung: `field-mapping.json` aktualisieren (Token-Lauf + manuelle
Semantik-Ergänzung), `npm run generate:fields`, dann Phase 1 planen.
