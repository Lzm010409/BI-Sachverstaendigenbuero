# Strategie — Kürzungsschreiben-Zuordnung, Zahlungsverlauf & Massen-PDF-Parsing

Entwurf zum Gegenlesen (2026-07-16). Zwei vom Inhaber angefragte Strategien. Beide
hängen an einer gemeinsamen Fähigkeit: **PDFs zuverlässig parsen und dem Fall
zuordnen** — daher zusammen gedacht.

---

## M365-Machbarkeit — BEWIESEN (2026-07-16, Fall 0625/1630TG)

Über den M365-Konnektor (Graph) getestet:
- **OneDrive/SharePoint:** sauberer Ordner je Fall
  (`…/Sachverstaendigerei/Gutachten/JJJJ/MM/MMJJ_NummerTG/`) mit Gutachten-PDF,
  Rechnung, Anschreiben, Aufnahmebogen, WBW-Belegen und einer **`vxs.xml`**
  (strukturierte DAT-Kalkulation).
- **`read_resource` liefert den vollen PDF-Text** (Text-Layer, kein OCR). Die
  „Zusammenfassung des Gutachtens" auf Seite 2 trägt ALLE Fachwerte in konstantem,
  beschriftetem Format: Reparaturkosten netto/brutto, WBW, Wertminderung, Restwert
  (bzw. „nicht ermittelt"), Nutzungsausfall/Tag, Beurteilung (Reparatur-/Total-
  schaden). → **hochzuverlässig parsebar (Label-Regex oder LLM).**
- **Phase 4 ist damit über OneDrive unblockiert — ohne autoiXpert-API.**
- **Outlook:** Gutachten-Korrespondenz mit Aktenzeichen im Betreff; Kürzungs-/
  Regulierungsschreiben kommen meist als **PDF-Anhang** (u. a. über die Kanzlei mit
  *deren* Az) → Zuordnung über den **Anhang-Inhalt** (Gutachtennummer/Kennzeichen),
  nicht den Betreff.

## Ausgangsbefund (an Prod-Daten belegt)

- **Ausbuchung** ist zuverlässig: sevDesk-Belege „Forderungsverlust <Aktenzeichen>"
  (89 Fälle / 34 k€ live). = der tatsächliche Verlust.
- **Kürzung** ist NICHT aus sevDesk ableitbar: die Rechnung wird bei Abschluss voll
  gebucht (Zahlung + Ausbuchungsbuchung), offener Betrag ~0 trotz realer Abschreibung.
  → Die echte Kürzung (Versicherer-Behauptung, mit Zeitpunkt) steht **nur im
  Kürzungsschreiben**. Das ist die Lücke, die Strategie 1 schließt.

---

## Kürzungsschreiben — Format an echtem Sample verifiziert (2026-07-16)

Beispiel: Allianz-Regulierung zu Fall `0224/1101TG` (`…/Gutachten/2024/02/0224_1101TG/
Vers ABRECHNUNG.pdf`; weitere in Fallordnern, z. B. `2023.05.15 Allianz Kürzung SV
Kosten.pdf`, `Regulierungsschreiben.pdf`). Befunde:

- **Kürzungsbetrag explizit** im Text: „**831,57 EUR Kürzungsbetrag**" (in der
  beigefügten Abtretungsvereinbarung). Das ist die gesuchte initiale Kürzung.
- **Aktenzeichen steht im Dokument** — als Rechnungsnummer „0224/11 01TG01"
  (Leerzeichen = OCR-Artefakt) → normalisiert `0224/1101TG`. Damit **Zuordnung über
  den Dokument-Inhalt** (nicht Betreff/Dateiname), robust.
- **Zahlungs-Breakdown** vorhanden: Reparaturkosten netto, Sachverständigenkosten
  (gezahlt), Wertminderung, Kostenpauschale, Zahlungsbetrag; Versicherer (Allianz),
  Schadennummer (AS2024-…). → speisen Kürzungsereignis + Zahlungsverlauf.
- **CAVEAT — Scans:** Manche Schreiben haben KEINEN Text-Layer (reiner Scan; das
  erste Allianz-PDF lieferte leeren Text). → **OCR-Fallback nötig.** Wegen
  Versicherer-Formatvielfalt ist **LLM-Extraktion mit striktem JSON-Schema**
  (Kürzungsbetrag, Aktenzeichen, Versicherer, Schadennummer, Datum, Positionen)
  robuster als Regex und deckt Scan (nach OCR) wie Text ab.

## Strategie 1 — Kürzungsschreiben erfassen, zuordnen & Zahlungsverlauf

**Ziel:** je Fall eine Zeitleiste „Zahlung 01.06. → 150 €, Kürzung 15.06. → 80 €
(Grund) …", damit sichtbar wird, *wie viel wann warum* gekürzt wurde → echte
Durchsetzungsquote (Kürzung vs. Ausbuchung/Forderungsverlust).

**Datenfluss (Vorschlag, n8n-getrieben):**
1. **Intake** des Kürzungsschreibens: E-Mail-Postfach (Outlook-Trigger, wie das
   bestehende autoiXpert-Job-Postfach) oder OneDrive-Ordner. PDF landet in n8n.
2. **Parsen** (LLM-Extraktion, s. gemeinsamer Baustein unten) → strukturiert:
   Kürzungsbetrag(e), Kürzungsgrund, Datum, und ein **Zuordnungsschlüssel**.
3. **Zuordnen** zum Fall: primär unser **Aktenzeichen**/Rechnungsnummer (steht meist
   im Schreiben); Fallback über die **Schadennummer des Versicherers**
   (`insurance.contract_number`/`case_number` aus autoiXpert — nur zum Matchen, nicht
   speichern). Keine Zuordnung → Klärfall-Liste statt stiller Verwurf.
4. **Speichern** der Ereignisse zweigleisig:
   - **n8n Data Table `kuerzungsverlauf`** (aktenzeichen, datum, typ [Kürzung],
     betrag, grund, quelle) → ETL liest sie nach `raw` → `core.fact_kuerzungsereignis`
     → Zeitreihe/Durchsetzungs-Views. (Analytik.)
   - **Pipedrive-Notiz/Activity** am Deal (operative Sicht: die „Liste im Pipedrive").
5. **Zahlungen** dazu: sevDesk führt Einzelzahlungen als CheckAccountTransactions /
   Invoice-Bookings (Datum + Betrag). Ein Extraktor `extract-payments` zieht sie je
   Rechnung → `core.fact_zahlung`. Kürzungsereignisse + Zahlungen zusammen = die
   vollständige Zeitleiste.

**Ergebnis:** `Durchsetzungsquote = 1 − Σ Ausbuchung(Beleg) / Σ Kürzung(Schreiben)`
wird endlich belastbar; zusätzlich der Zahlungs-/Kürzungsverlauf je Fall.

**Entscheidungen (Inhaber):** (a) Intake per E-Mail oder OneDrive? (b) Kommt das
Aktenzeichen zuverlässig im Kürzungsschreiben vor? (c) Zeitleiste in Pipedrive als
Notiz genügt, oder eigenes Feld/Liste?

---

## Strategie 2 — Massen-PDF-Parsing für Phase 4 (Fachwerte WBW/Restwert/…)

**Ziel:** WBW, Restwert, Wertminderung, Reparaturkosten aus den Gutachten-PDFs, die
in Pipedrive/der API fehlen → Leitfragen 8 (BVSK) & 10 (Totalschaden).

**Quelle — Empfehlung autoiXpert-externalApi statt OneDrive:** die relevanten Zahlen
stehen in klar benannten DAT-Dokumenten, die die externalApi je Report als PDF
liefert (`dat_market_analysis` → WBW, `dat_damage_calculation` → Reparatur,
`custom_residual_value_bid_list` → Restwert, `diminished_value_protocol` →
Wertminderung — Existenz führt `fact_gutachten.dokumente` bereits). Vorteil ggü.
OneDrive: sauber je Aktenzeichen zuordenbar (kein Datei-Matching), ein bestehender
n8n-Workflow lädt DAT-PDFs schon herunter. OneDrive bleibt Backfill-Quelle für
Altfälle.

**Permanente Lösung (n8n):**
1. **Trigger:** Report wird `done` (bzw. nächtlich über Reports mit DAT-Dokumenten).
2. **Download** der DAT-PDFs über die externalApi (vorhandenes Muster).
3. **Extraktion** (LLM, gemeinsamer Baustein) → JSON {wbw, restwert, wertminderung,
   reparatur_netto/brutto, nutzungsausfall}, **validiert** (WBW ≥ Restwert; Werte ≥ 0;
   Totalschaden = Reparatur > WBW).
4. **Speichern** in Data Table `gutachten_fachwerte` (aktenzeichen + Zahlen) → ETL →
   `raw.autoixpert_fachwerte` → `core.fact_gutachten` (die Phase-4-Views stehen als
   Entwurf) → `v_bvsk_korridor`, `v_totalschaden_quote`.
5. **Backfill** einmalig über alle done-Reports/OneDrive-Archiv.

**DSGVO:** nur die Zahlen extrahieren; VIN/Kennzeichen/Klarnamen/Freitexte aus dem
PDF werden NICHT persistiert (gleiche Option-A-Whitelist wie Phase 4).

---

## Gemeinsamer Baustein — PDF → strukturierte Zahlen

Beide Strategien brauchen dasselbe: aus einem PDF verlässlich Zahlen ziehen.

- **Verfahren:** Text-Layer (autoiXpert/DAT-PDFs sind kein Scan) + **LLM-Extraktion
  gegen ein striktes JSON-Schema**, mit Plausibilitätsregeln als Validierung. Robust
  gegen Layout-Varianten; deterministische Regex-Anker als Fallback/Kreuzcheck.
- **Wo:** in n8n (LLM-Node) für den Dauerbetrieb; die Zahlen fließen über eine Data
  Table in den bestehenden ETL. Kosten pro Dokument klein.
- **Prototyp zuerst:** an 1–2 echten PDFs die Extraktion + das Schema festklopfen
  (Genauigkeit messen), dann in n8n produktiv setzen. Aus der Web-Session ist der
  autoiXpert-Egress geblockt → für den Prototyp brauche ich 1–2 Beispiel-PDFs vom
  Inhaber; der Dauerbetrieb läuft ohnehin in n8n/Coolify.

**Entscheidungen (Inhaber):** (a) LLM-Extraktion in n8n ok (kleiner Kosten-/Datenfluss
pro Dokument)? (b) Für den Prototyp 1–2 Gutachten- + 1 Kürzungsschreiben-PDF liefern?
(c) Reihenfolge: erst Kürzungsschreiben (Strategie 1, schaltet Durchsetzungsquote
frei) oder erst Fachwerte (Strategie 2, schaltet Phase 4 frei)?
