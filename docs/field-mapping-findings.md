# Feldmapping — Recon-Findings & offene Entscheidungen (Phase 0)

**Stand:** 2026-07-15
**Quelle:** Live-Stichproben über den **Pipedrive-OAuth-MCP** (`getDeals`/
`getOrganizations`/`getStages` mit `include_option_labels=true` und
`include_labels=true`, u. a. ein 100-Deal-Scan). Der MCP stellt **kein**
Feldmetadaten-Endpoint bereit — Feld-*labels* bleiben daher aus Werten
abgeleitet, nicht aus der API-Metadaten gelesen. Diese Datei ist der
Gegenlese-Gegenstand für die 🧑-MENSCH-Punkte aus Phase 0.

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

## 3. Selbst-geprüfte Hypothesen (100-Deal-Scan) — Ergebnis

Der MCP liefert keine Metadaten; ich habe die ❓ stattdessen über einen
100-Deal-Scan datenbasiert geprüft. Ergebnis:

| Feld | Alte Vermutung | **Befund aus dem Scan** | Reststatus |
|---|---|---|---|
| `215832fc…` | Nutzungsausfall-Tagessatz | 86/100 befüllt, ganzzahlig 128–301 (Cluster bei 128), **r=−0,01 zu deal_value** → kein Honorar, wirkt wie Tabellenwert. Tagessatz-Hypothese plausibel, aber **nicht** als Paar mit Tage-Feld. | unbestätigt |
| `4476af41…` | Nutzungsausfall-Tage | **0/100 befüllt** (früher nur 4/17). Nahezu ungenutzt. → „Rate×Tage"-These verworfen. | irrelevant/ offen |
| `efd97e60…` / `3bc5c0f3…` | Vor-/Altschaden | Bestätigt: **zwei eigenständige Ja/Nein-Felder** (Optionen 53/54 bzw. 55/56). | Zuordnung Vor↔Alt noch zu bestätigen |
| `cff1b2f6…` | Schadendatum | **Immer < add_time (81/81)**, = Erstzulassung bei Neukauf, danach bei Gebrauchtkauf → **Erwerbs-/Anschaffungsdatum**, nicht Schadendatum. | Hypothese revidiert, bitte bestätigen |
| `62a4930b…` | Besichtigung/Rechnung | nur 13/100 befüllt, gemischt vor/nach `won_time`. | offen |
| `621afa76…`, `b189ecbd…`, Org-Felder | unbekannt | im Scan durchgängig null. | offen (Wissen Inhaber) |

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

## 5. `label_ids` entschlüsselt — Vollständiger Katalog in `labels.md`

Deal-Labels sind **drei Bedeutungsgruppen in einem Feld** (Details + Häufigkeiten
in `docs/labels.md`):

- **Gutachtenart:** 28 = Haftpflichgutachten (98/100), 36 = BEWERTUNG (2/100).
- **Fall-Alterung:** 61 Neuer / 62 Mittelalter / 63 Überfälliger Fall (auto).
- **Fall-Flag:** **60 = „OHNE RECHTSANWALT"** — jetzt geklärt, **keine**
  Gutachtenart, sondern ein Flag (Fall ohne Anwalt).

**Zentrale Erkenntnis für Leitfrage 1:** Pipedrive unterscheidet faktisch nur
**Haftpflicht vs. Bewertung**. Die feingliedrige Gutachtenart (Kasko,
Kurzgutachten, Reparaturbestätigung, Beweissicherung, Leasingrückläufer …)
existiert **nicht** in Pipedrive-Labels → die Auftragsart-Dimension muss aus
**autoiXpert** (Phase 4) kommen. Der ETL leitet aus `label_ids` nur die grobe
Art {28, 36} ab.

- **MENSCH (Q4):** Bestätigst du, dass die feine Gutachtenart aus autoiXpert
  kommt? Und: welche Arten willst du als **eigene Auswertungsdimension** (das ist
  zugleich der in Phase 4 gewünschte Katalog)? Das ist der einzige Teil von Q4,
  den ich nicht aus den Daten holen kann.
- Org-Labels **32/35** bestätigt (siehe `labels.md`); gibt es weitere (z. B.
  Werkstätten)?

---

## 6. Offene 🧑-MENSCH-Punkte aus Phase 0 (Checkliste)

- [x] Pipedrive-Zugang geklärt: **OAuth-MCP** (kein separater REST-Token).
      `fetch-field-mapping.ts` bleibt als Fallback, falls je ein OAuth-REST-Token
      bereitsteht (MCP liefert keine Feldmetadaten).
- [x] `org_id`: Prozess **wird laut Inhaber verbessert**. Befüllung aktuell
      51/100. ETL behandelt fehlende `org_id` explizit als „ohne
      Versicherer-Zuordnung", nie coalescen.
- [x] Hypothesen datenbasiert geprüft (Abschnitt 3). Rest-Bestätigungen offen:
  - [ ] `cff1b2f6…` = Erwerbsdatum? (revidiert von Schadendatum)
  - [ ] `215832fc…` = Nutzungsausfall-Tagessatz? (Label nicht aus Daten ableitbar)
  - [ ] Zuordnung `efd97e60…`↔Vorschaden vs `3bc5c0f3…`↔Altschaden
  - [ ] `62a4930b…` Datum, `621afa76…`/`b189ecbd…`/Org-Felder
- [ ] **Q4 (offen):** feine Gutachtenart aus autoiXpert bestätigen + Katalog der
      auswertungsrelevanten Arten liefern (Abschnitt 5).
- [ ] **GitHub-Schreibrecht** für die Claude-App, damit Phase 0 gepusht werden
      kann (git-Relay ist read-only, App-Integration ohne Schreibrecht).

Diese Rest-❓ blockieren Phase 1 (Infrastruktur) **nicht**. Sie müssen vor der
`fact_ausbuchung`-Modellierung in Phase 2 geschlossen sein.
