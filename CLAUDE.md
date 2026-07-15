# CLAUDE.md — BI-Plattform Kfz-Sachverständigenbüro

Data Warehouse + BI-Layer für ein unabhängiges Kfz-Sachverständigenbüro.
Diese Datei ist die verbindliche Referenz für jede Arbeit am Repo. Sie wird zu
Beginn jeder Session gelesen.

---

## Zweck

Nicht "Zahlen zeigen", sondern konkrete Entscheidungen stützen. Jede Kennzahl
zahlt auf genau eine der zehn Leitfragen ein. Wer eine Kennzahl baut und nicht
sagen kann, auf welche Frage sie einzahlt, hört auf und fragt nach.

### Die zehn Leitfragen

1. Welche Auftragsart trägt welchen Deckungsbeitrag?
2. Welcher Versicherer kürzt wie oft, mit welchem Betrag, aus welchem Grund?
3. Welche Kürzungen setze ich per Stellungnahme durch — lohnt sich der Aufwand?
4. Welche Auftragsquelle bringt Umsatz *und* zahlt zuverlässig?
5. Wo entstehen Zahlungsausfälle?
6. Wie lang sind die Durchlaufzeiten und wo klemmt es?
7. Umsatz je gefahrenem Kilometer, je Einzugsgebiet?
8. Honorar gegenüber Schadenhöhe (BVSK-Korridor)?
9. Saisonalität des Auftragseingangs — Kapazität oder Akquise?
10. Totalschaden-/130-%-Quote und Korrelation mit Kürzungen?

---

## Domänenregeln — nicht verhandelbar

Diese Regeln sind mehrfach bestätigt. Sie stehen über jedem Codekommentar und
jeder API-Doku. Wer sie verletzt, produziert Zahlen, die plausibel aussehen und
falsch sind — der schlimmste Fehlermodus dieses Projekts.

- **Aktenzeichen** hat das Format `MMJJ/NummerTG`, z. B. `0225/1505TG`.
  Es ist der Join-Key über alle Systeme. Der Pipedrive-Deal-Titel **ist** das
  Aktenzeichen. Normalisierung: Großschreibung, keine Leerzeichen.
  Validierung gegen `^\d{4}/\d+TG$`.

- **Alle Beträge sind brutto.** Deal-Value, Ausbuchungsbetrag, Rechnungssumme.
  Keine stillschweigende Netto-Umrechnung, nirgends.

- **`null ≠ 0` beim Ausbuchungsbetrag.** `0` heißt "geprüft, voll bezahlt".
  `null` heißt "nie erfasst". Wer `null` zu `0` coalesced, fälscht die
  Ausbuchungsquote. In `fact_ausbuchung` bleibt `null` erhalten, und jede
  Auswertung filtert explizit auf `IS NOT NULL`.

- **`won_time` ist das Ausbuchungsdatum.** Ein Deal wird genau dann auf `won`
  gesetzt, wenn er geschlossen wird — entweder voll bezahlt, oder teilweise
  bezahlt und der Rest ausgebucht. Kein separates Datumsfeld nötig.

- **Fachbegriffe werden nie übersetzt oder eingedeutscht.** Wiederbeschaffungswert
  (WBW), Restwert, Wertminderung (merkantiler Minderwert), Nutzungsausfall,
  UPE-Aufschläge, Verbringungskosten, Stundenverrechnungssätze, Vorschaden,
  Altschaden, Beweissicherung, Reparaturbestätigung. In Spaltennamen: deutsche
  Begriffe, snake_case, ASCII (`wiederbeschaffungswert`, `wertminderung`).

- **Ausbuchung ≠ Kürzung.** Die Kürzung ist, was der Versicherer *behauptet*.
  Die Ausbuchung ist, was am Ende *tatsächlich* verloren ist. Die Differenz ist
  die Durchsetzungsquote und damit die wichtigste Zahl im ganzen System.
  Zwei getrennte Fakten, niemals vermischen.

- **Haftungsquote ist keine Kürzung.** Wenn die Gegenseite nur zu 50 % haftet,
  hat der Versicherer korrekt reguliert. Landet das im selben Topf wie
  Nebenkostenkürzungen, sieht ein korrekter Versicherer schlecht aus und die
  Kennzahl ist wertlos. Eigene Kategorie, eigene Auswertung.

- **DSGVO:** Keine Klarnamen von Geschädigten, keine VIN, **kein Kennzeichen** im
  Warehouse. Personenbezug nur als pseudonyme ID. Versicherer, Werkstätten und
  Anwaltskanzleien sind juristische Personen — die dürfen im Klartext stehen.
  Freitextfelder (Unfallhergang, Schadenbeschreibung) werden **nicht** ins
  Warehouse übernommen; sie enthalten regelmäßig Personenbezug.

---

## Architektur (Zielstack)

```
Quellen ──> ELT (TypeScript-Repo, Cron-Container) ──> PostgreSQL ──> Metabase OSS
                                                       raw / core / marts
n8n bleibt für Ereignisgetriebenes (Mail-Eingang -> Abrechnungs-Pipeline).
```

Marginale Kosten ≈ 0, alles auf bestehendem Coolify.

**Bewusst NICHT verwenden:** dbt (Overhead bei dieser Größe — SQL-Views reichen,
bis es >20 Modelle sind), Power BI, Cloud-Warehouses, Airflow.

### Schema-Konvention

- `raw`   — Rohantworten der Quellen, unverändert, JSONB. **Heilig.**
- `core`  — normalisierte Fakten und Dimensionen (`fact_*`, `dim_*`).
- `marts` — Views für Metabase (`v_*`).

---

## Repo-Konventionen

- **Sprache:** TypeScript (Bestandscode der n8n-Code-Nodes ist JavaScript).
- **SQL-Migrationen** nummeriert: `sql/001_raw.sql`, `002_core.sql`, …
  Idempotent, Zustandstabelle `_migrations`, laufen beim Container-Start.
- **Keine rohen Pipedrive-Hash-Keys im Code.** Feldzugriff ausschließlich über
  benannte Konstanten aus `etl/pipedrive/fields.generated.ts`. Die Datei wird
  aus `docs/field-mapping.json` generiert, nie von Hand editiert.
- **Rohdaten sind heilig.** `raw` wird nie überschrieben, transformiert oder
  gelöscht. Jede Transformation ist aus `raw` reproduzierbar.
- **Secrets** kommen aus der Umgebung, nie ins Repo, nie in Logs. `.env` ist
  gitignored; Vorlage in `.env.example`.
- **Kein Schreibzugriff auf Produktivsysteme**, außer explizit freigegeben
  (nur Phase 5, nur nach Shadow Mode). ETL-Tokens sind read-only.
- **API-Details immer gegen die aktuelle Doku prüfen**, nie aus dem Gedächtnis
  (Pipedrive, sevDesk, autoiXpert, Metabase).
- **Bei Unklarheit fragen, nicht annehmen.** Besonders bei Netto/Brutto und
  `null`/`0`.
- **Pro Phase ein Branch.** Vor jeder Phase erst ein Plan, der gegengelesen wird,
  dann bauen. Bei Datenmodellierung ist der Plan die Arbeit.

### Zeit/Zeitzonen

- Alle Zeitstempel als `timestamptz`, UTC. Pipedrive liefert UTC; die
  `local_*_date`-Felder sind lokal — nicht verwechseln.

---

## Join-Keys über die Systeme

| Key | Quelle | Ziel | Feld |
|---|---|---|---|
| Aktenzeichen | Pipedrive `deal.title` | alle | primär, normalisiert |
| sevDesk-Rechnungs-ID | Pipedrive Custom Field | sevDesk | sekundär |
| autoiXpert-Gutachten-ID | Pipedrive Custom Field | autoiXpert | Phase 4 |

Siehe `docs/field-mapping.md` für die konkreten Hash-Keys und ihren Status.

---

## Wichtige Struktur-Erkenntnisse (Pipedrive)

- Pipeline `2`. Stages: `6 Aufgenommen → 7 In Bearbeitung → 8 Versendet →
  9 Teilbezahlt → 10 Bezahlt (Won) → 11 Klage`.
- **`deal.label_ids` mischt drei Gruppen** (Katalog: `docs/labels.md`):
  Gutachtenart (28 = Haftpflichgutachten, 36 = BEWERTUNG), Fall-Alterung
  (61/62/63), Fall-Flag (60 = OHNE RECHTSANWALT). Der ETL muss sie trennen.
  Die Gutachtenart-Dimension ist mit **Haftpflicht** und **Bewertung**
  **vollständig** — das Büro erstellt (bestätigt durch den Inhaber) nur diese
  beiden Arten. autoiXpert liefert in Phase 4 weitere Fachdaten (WBW, Restwert,
  Wertminderung …), aber **keine** zusätzliche Auftragsart.
- **Organisationen sind typisiert über `org.label_ids`:** 35 = Versicherer,
  32 = Auftraggeber/Anwalt/Privat. `deal.org_id` referenziert — wenn gesetzt —
  den Versicherer, ist aber **dünn befüllt**. Das ist die zentrale offene Lücke
  für Leitfrage 2 (siehe `docs/field-mapping.md`).

---

## Phasenreihenfolge (Abhängigkeiten)

0 Fundament → 1 Infrastruktur → 2 Pipedrive→fact_ausbuchung→Metabase →
3 sevDesk positionsscharf → 4 autoiXpert → 5 Kürzungsgrund (braucht Phase 3!) →
6 Legacy-Backfill → 7 Dashboards & Betrieb.

Reihenfolge einhalten: Phase 5 braucht die sevDesk-Positionen aus Phase 3.
