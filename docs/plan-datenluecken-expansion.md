# Plan — Datenlücken & Expansions-Readiness

Stand: 2026-07-21. Grundlage: Live-Analyse des Warehouse-Bestands (nicht der
Planung). 1.006 Fälle seit Okt. 2024, davon 889 won, 116 open, 1 lost.

Leitgedanke: Die zehn Leitfragen sind **strukturell vollständig** beantwortbar —
für jede existiert mindestens eine View und Karte. Die offene Frage ist nicht
mehr „fehlt eine Quelle?", sondern zweierlei:
1. Wie gut sind die vorhandenen Dimensionen **befüllt**? (Bestandspflege)
2. Welche Daten fehlen für die **Expansions-Entscheidung** komplett? (Neuerhebung)

---

## Teil A — Lücken im vorhandenen Bestand (Abdeckung, live gemessen)

| Dimension | Abdeckung | Hebel |
|---|---|---|
| Geo je Fall | ~100 % | — vollständig |
| Versicherer je Fall (LF2) | 77 % | wächst automatisch über autoiXpert |
| Gutachten-Fachwerte (LF8/10) | 60 % | 2026er laufen automatisch nach; Altbestand nur per Backfill |
| Beauftragungsherkunft (LF4) | 30 % | historischer Snapshot, wächst nicht von allein |
| Auftragsquelle konkret (LF4) | 2 % | erst ab 2026 via autoiXpert; braucht Feld-Pflege bei Fallanlage |
| **Kürzungsgrund (LF2/5)** | **~3 %** | **größte Schwachstelle: 836 von 861 Kürzungen „ohne Grund"** |

**Prio A1 — Kürzungsgrund-Backfill ausbauen.** Die Briefe liegen vor; nur die
erste OCR-Scheibe ist geparst. „Warum kürzt welcher Versicherer" (Kern von LF2)
ist heute faktisch unbeantwortet. Re-OCR der restlichen Kürzungsschreiben-Varianten.

**Prio A2 — Herkunfts-/Quellenfelder im Tagesgeschäft pflegen.** Rein
prozessual: autoiXpert-Vermittlerfeld + Herkunftskanal konsequent bei Fallanlage
setzen, dann wächst LF4 von allein.

---

## Teil B — Nicht erhobene Daten (nach Expansions-Nutzen sortiert)

### B1 — Zeitaufwand je Fall  *(größter blinder Fleck)*
Der Deckungsbeitrag rechnet mit Fix-Kosten-Umlage, nicht mit echtem Aufwand.
Damit sind LF1 (welche Auftragsart lohnt sich), LF3 (lohnt die Stellungnahme)
und LF9 (Kapazität vs. Akquise) nur halb beantwortbar.
- **Erhebung:** ein Feld „Aufwand in Stunden" je Fall (grobe Schätzung bei
  Abschluss, optional getrennt Gutachten/Stellungnahme).
- **Anbindung:** Pipedrive Custom Field → bestehender ETL.
- **Voraussetzung:** Inhaber muss die Erfassung im Alltag mittragen.

### B2 — Anfrage-Funnel / lost-Deals  *(wichtigste Expansionszahl)*
Im Bestand: **genau 1 lost-Deal.** Pipedrive erfasst nur, was Auftrag wurde.
Abgesprungene Anfragen (Preis? Entfernung? Kapazität?) hinterlassen keine Spur —
dabei ist „wie viel Nachfrage lehnen wir ab, und warum?" die zentrale
Expansionsfrage.
- **Erhebung:** jede Anfrage als Deal anlegen; verlorene mit `lost_reason` schließen.
- **Anbindung:** Status/Stage-Historie werden bereits extrahiert — BI-seitig sofort auswertbar.
- **Voraussetzung:** Prozessdisziplin.

### B3 — Reaktionszeit bis Besichtigung
`fact_durchlauf` misst ab Fallanlage über Stages, aber der Besichtigungstermin
selbst fehlt. „Anfrage → Besichtigung" ist *das* Wettbewerbs- und Standortkriterium.
- **Erhebung:** Besichtigungsdatum in autoiXpert oder als Pipedrive-Activity.

### B4 — Externe Marktdaten fürs Expansions-Benchmarking  ← **DIESER SCHRITT**
Saubere Geo-Sicht vorhanden (Umsatz je PLZ-Gebiet, je km), aber nichts zum
Normieren. Ein Fixture aus öffentlichen Quellen (Kfz-Bestand + Verkehrsunfälle
je Kreis) macht aus „wo verdienen wir viel" die eigentliche Frage:
**„wo ist viel Markt, den wir NICHT abdecken?"** — Marktausschöpfung je Region.
- **Erhebung:** einmaliges Fixture, reine BI-Arbeit, keine Prozessänderung.
- **Umsetzung:** siehe Teil C.

### B5 — Echte Kostenseite
Für eine Standortrechnung fehlen Personal-, Fahrzeug- und Fixkosten als gepflegte
Größen. Kleines, quartalsweise gepflegtes Kosten-Fixture → Deckungsbeitrag von
„Näherung" auf „belastbar".

### B6 — Nachrangig
Zufriedenheits-/Weiterempfehlungssignal je Werkstatt-/Anwaltspartner (Bindung der
wichtigsten Kanäle); die 108 Stellungnahme-Schreiben als eigene LF3-Quelle
(steht als Ausbaupunkt in STATUS.md).

---

## Teil C — Umsetzung B4: Marktdaten-Fixture (dieser Schritt)

**Ziel:** Marktausschöpfung je Region = eigene Fälle / Marktpotenzial. Deckt die
Expansions-Frage „wo ist unbearbeiteter Markt?" ab, ohne Prozessänderung.

**Regionsschlüssel:** Kreis (Landkreis / kreisfreie Stadt), amtlicher
Kreisschlüssel (AGS, 5-stellig). Join zum Bestand über PLZ→Kreis-Zuordnung des
vorhandenen Geo-Layers (`core.dim_fall_geo`).

**Kennzahlen je Kreis (öffentlich, verifizierbar — NICHT geschätzt):**
- Kfz-Bestand (KBA, Bestand nach Zulassungsbezirken, jährlich).
- Verkehrsunfälle mit Personenschaden bzw. Gesamtunfälle (Destatis / statistische
  Landesämter, je Kreis, jährlich).
- Einwohner (Destatis, je Kreis) — für Normierung.

**Artefakte:**
- `fixtures/markt_kreis.csv` — `ags;kreis;bundesland;einwohner;kfz_bestand;unfaelle_gesamt;jahr;quelle`
- `etl/load-markt-kreis.ts` — TRUNCATE+INSERT nach `core.dim_markt_kreis` (Muster wie honorar-referenz)
- `sql/060_marktdaten.sql` — `core.dim_markt_kreis` + PLZ→Kreis-Brücke +
  `marts.v_marktausschoepfung` (eigene Fälle/Umsatz je Kreis gegen Kfz-Bestand/Unfälle)
- Loader in docker-compose + package.json

**Datenintegrität (CLAUDE.md):** Referenzwerte kommen ausschließlich aus zitierten
öffentlichen Quellen (Quelle + Jahr je Zeile in der CSV). Keine erfundenen Werte —
das ist der schlimmste Fehlermodus. Solange eine Kennzahl nicht belegt beschafft
ist, bleibt sie in der CSV leer (NULL), nicht geraten.

**Scope:** zunächst die real bearbeiteten Kreise (aus dem Geo-Layer abgeleitet),
nicht ganz Deutschland — das hält das Fixture pflegbar und relevant.
