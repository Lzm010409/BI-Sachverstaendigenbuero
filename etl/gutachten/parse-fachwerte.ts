/**
 * parse-fachwerte.ts — extrahiert die Fachwerte aus dem TEXT eines autoiXpert-
 * Gutachtens (Haftpflicht/Bewertung). Quelle: die „Zusammenfassung des Gutachtens"
 * auf Seite 2, die in jedem Gutachten in konstantem, beschriftetem Format steht.
 *
 * DSGVO: liefert AUSSCHLIESSLICH numerische Fachwerte + Klassifikation. KEIN VIN,
 * KEIN Kennzeichen, KEIN Klarname, keine Freitexte — die restlichen 37 Seiten
 * (Ausstattung, Kalkulationspositionen, Fotos, Halterdaten) werden ignoriert.
 *
 * Whitespace-tolerant (funktioniert mit unterschiedlichen PDF-Text-Extraktoren):
 * Zeilenumbrüche/Mehrfach-Spaces werden vor dem Matchen zu je einem Space normiert.
 * Deutsche Zahlen „14.035,01" -> 14035.01.
 */

export interface Fachwerte {
  aktenzeichen: string | null;
  wiederbeschaffungswert: number | null;
  restwert: number | null;
  wertminderung: number | null;
  reparaturkosten_netto: number | null;
  reparaturkosten_brutto: number | null;
  schadenhoehe_brutto: number | null;
  nutzungsausfall_tagessatz: number | null;
  reparaturdauer_tage: number | null;
  beurteilung: string | null; // z. B. "Reparaturschaden", "Totalschaden"
}

/** „14.035,01" | „65.000,00" -> number; sonst null. */
function deNum(s: string | undefined | null): number | null {
  if (!s) return null;
  const n = Number(s.replace(/\./g, "").replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

function firstNum(text: string, re: RegExp): number | null {
  const m = text.match(re);
  return m ? deNum(m[1]) : null;
}

/**
 * Extrahiert die Fachwerte aus dem Gutachten-Volltext. `aktenzeichenHint` (aus dem
 * Dateinamen/Ordner) wird als Fallback genutzt, falls im Text nicht auffindbar.
 */
export function parseFachwerte(rawText: string, aktenzeichenHint?: string): Fachwerte {
  // Whitespace normieren: alle Folgen aus Space/Umbruch -> ein Space.
  const t = rawText.replace(/\s+/g, " ");

  // Aktenzeichen: „Gutachten 0625/1630TG" (normalisiert, Großschrift).
  const azMatch = t.toUpperCase().match(/\b(\d{4}\/\d+TG)\b/);
  const aktenzeichen: string | null = azMatch?.[1] ?? aktenzeichenHint ?? null;

  // Format der „Zusammenfassung" (autoiXpert, Stand 2026, an echten PDFs verifiziert):
  //   „Reparaturkosten ohne MwSt.   1.957,20 €"          (Betrag + € nachgestellt, KEIN EUR)
  //   „Reparaturkosten inkl. MwSt. (371,87 €)   2.329,07 €"  (Klammerbetrag überspringen)
  //   „Wiederbeschaffungswert (differenzbesteuert)   3.800,00 €"
  //   „Nutzungsausfall Entschädigung pro Tag (Gruppe A)   23,00 €"
  //   „Reparaturdauer   ca. 2 Arbeitstage"
  // Beträge sind brutto (Domänenregel). Bewertungen (Oldtimer) tragen den Wert oft nur
  // als Note/Bild → dann bleiben die Zahlen null, beurteilung = „Bewertung".
  // ANKER-STRATEGIE: primär auf die FLIESSTEXT-Vorkommen (Seiten „Gesamtsummen",
  // „Wiederbeschaffungswert", „Restwert", „Nutzungsausfall", „Beurteilung"), weil
  // pdf-parse Prosa zuverlässig linearisiert; die zweispaltige Zusammenfassungs-Tabelle
  // (S. 2) ordnet es dagegen um. Zweitanker = das Tabellenformat (falls Prosa fehlt).
  // HINWEIS: pdf-parse hängt in der Zusammenfassung Label und Betrag OHNE Leerzeichen
  // aneinander („MwSt. (371,87 €)2.329,07 €") — daher überall \s* (nicht \s+) vor der Zahl.
  const reparaturkosten_netto =
    firstNum(t, /Reparaturkosten\s+ohne\s+MwSt\.\s*([\d.,]+)\s*€/i) ??  // Zusammenfassung
    firstNum(t, /Reparaturkosten\s+netto\s*([\d.,]+)/i);                // Gesamtsummen-Block
  const reparaturkosten_brutto =
    firstNum(t, /Reparaturkosten\s+inkl\.?\s+MwSt\.\s*\([^)]*\)\s*([\d.,]+)\s*€/i) ??
    firstNum(t, /Reparaturkosten\s+brutto\s*([\d.,]+)/i);

  const schadenhoehe_brutto =
    firstNum(t, /Schadenh[öo]he\s+inkl\.?\s+MwSt\.\s*\([^)]*\)\s*([\d.,]+)\s*€/i);

  // Wertminderung: nur wenn ausgewiesen (oft „(keiner)" -> 0).
  const wertminderung = /Merkantiler Minderwert\s*\(kein/i.test(t)
    ? 0
    : firstNum(t, /Minderwert(?:\s*\([^)]*\))?\s*:?\s*([\d.,]+)\s*€/i);

  // WBW brutto: Fließtext „Wiederbeschaffungswert: 3.800 €"; sonst Tabellenform mit Klammer.
  const wiederbeschaffungswert =
    firstNum(t, /Wiederbeschaffungswert\s*:\s*([\d.,]+)\s*€/i) ??
    firstNum(t, /Wiederbeschaffungswert\s*\([^)]*\)\s*([\d.,]+)\s*€/i);

  const nutzungsausfall_tagessatz = firstNum(t, /Entsch[äa]digung\s+pro\s+(?:Ausfall)?[Tt]ag(?:\s*\([^)]*\))?\s*:?\s*([\d.,]+)\s*€/i);

  // „Voraussichtlich ca. 2 Arbeitstage" (Fließtext); sonst Tabellen-Label.
  const reparaturdauer_tage = (() => {
    const m = t.match(/ca\.\s*(\d+)\s*Arbeitstag/i)
          ?? t.match(/Reparaturdauer\s+(?:ca\.?\s*)?(\d+)\s*Arbeitstag/i);
    return m?.[1] ? Number(m[1]) : null;
  })();

  // Restwert: „nicht ermittelt" -> null. Sonst „Restwert: 1.089,00 €" (Fließtext) / Tabelle.
  const restwert = /Restwert\s+wurde\s+nicht\s+ermittelt/i.test(t)
    ? null
    : (firstNum(t, /Restwert\s*:\s*([\d.,]+)\s*€/i) ??
       firstNum(t, /Restwert\s*(?:\(brutto\)\s*)?([\d.,]+)\s*€/i));

  // Beurteilung: „Schadenklasse: Reparaturschaden|Totalschaden" (Seite Beurteilung) bzw.
  // „Es handelt sich um einen …schaden" (Zusammenfassung); sonst Fahrzeugbewertung.
  const beurteilung: string | null = (() => {
    const sk = t.match(/Schadenklasse\s*:?\s*([A-Za-zÄÖÜäöüß]+schaden)/i);
    if (sk?.[1]) return sk[1];
    const eh = t.match(/Es handelt sich um einen\s+([A-Za-zÄÖÜäöüß]+schaden)/i);
    if (eh?.[1]) return eh[1];
    if (/Fahrzeugbewertung|Bewertungsergebnis|Wertsch[äa]tzung/i.test(t)) return "Bewertung";
    return null;
  })();

  return {
    aktenzeichen,
    wiederbeschaffungswert,
    restwert,
    wertminderung,
    reparaturkosten_netto,
    reparaturkosten_brutto,
    schadenhoehe_brutto,
    nutzungsausfall_tagessatz,
    reparaturdauer_tage,
    beurteilung,
  };
}
