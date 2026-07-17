# `etl/gutachten/` — Fachwerte-Parser aus Gutachten-PDFs

Ein einzelner, sehr wichtiger Baustein: `parse-fachwerte.ts` liest die Fachwerte
eines Gutachtens aus dem **PDF-Textlayer** (WBW, Restwert, Wertminderung,
Reparaturkosten netto/brutto, Nutzungsausfall-Tagessatz, Reparaturdauer, Beurteilung
Reparatur-/Totalschaden). Speist LF8 (Honorar vs. Schaden / BVSK) und LF10
(Totalschaden-/130 %-Quote).

## Wie es funktioniert

- Die autoiXpert-Gutachten (auch die alten Archive) haben auf Seite 2 eine
  **„Zusammenfassung des Gutachtens"** in **konstantem, beschriftetem Format** →
  ein Label-Regex-Parser ist hochzuverlässig (an echten Gutachten 10/10 Werte
  korrekt). Kein OCR nötig — der Textlayer reicht (nur die ersten ~3 Seiten).
- Der Parser bekommt den PDF-Text und gibt die **9 Whitelist-Zahlenfelder** zurück,
  mit Plausibilitätsregeln (netto×1,19 ≈ brutto; Totalschaden = Reparatur > WBW).

## Wer ruft es auf?

Nicht die Deploy-Kette, sondern **n8n**: der Reader-Workflow holt je Fall das
Gutachten-PDF aus OneDrive/SharePoint, extrahiert den Text und wendet diese Parser-
Logik an; das Ergebnis wird via Migration nach `raw.gutachten_fachwerte` geladen →
`core.fact_gutachten` (`sql/016`, Backfills `022`/`023`/`025`). Siehe `n8n/README.md`.

## DSGVO

Nur die 9 Zahlenfelder werden persistiert. **Nie**: VIN, Kennzeichen, Klarnamen,
Freitexte aus dem Gutachten.
