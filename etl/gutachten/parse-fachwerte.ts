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

  // Reparaturkosten: „... ohne MwSt. EUR 14.035,01" / „... mit 19,00 % MwSt. EUR 16.701,66"
  const reparaturkosten_netto = firstNum(t, /Reparaturkosten\s+ohne\s+MwSt\.?\s+EUR\s+([\d.,]+)/i);
  const reparaturkosten_brutto = firstNum(t, /Reparaturkosten\s+mit\s+[\d.,]+\s*%\s*MwSt\.?\s+EUR\s+([\d.,]+)/i);

  const schadenhoehe_brutto = firstNum(t, /Schadenh[öo]he\s+mit\s+[\d.,]+\s*%\s*MwSt\.?\s+EUR\s+([\d.,]+)/i);

  const wertminderung = firstNum(t, /Wertminderung\s+(?:\(netto\)\s+)?EUR\s+([\d.,]+)/i);

  // WBW: „Wiederbeschaffungswert mit 19,00 % MwSt. (regelbesteuert) EUR 65.000,00"
  // oder differenzbesteuert; tolerant bis zum ersten „EUR <zahl>" (erste Fundstelle
  // = Zusammenfassung auf S. 2, vor dem WBW-Fließtext). [\s\S] statt [^E], sonst
  // schlucken die „e" in „regelbesteuert" den Match (i-Flag macht [^E] = [^Ee]).
  const wiederbeschaffungswert = firstNum(t, /Wiederbeschaffungswert[\s\S]{0,80}?EUR\s+([\d.,]+)/i);

  const nutzungsausfall_tagessatz = firstNum(t, /Nutzungsausfall\s+pro\s+Tag\s+EUR\s+([\d.,]+)/i);

  const reparaturdauer_tage = (() => {
    const m = t.match(/Reparaturdauer\s+in\s+Arbeitstagen\s+(\d+)/i);
    return m ? Number(m[1]) : null;
  })();

  // Restwert: explizit „nicht ermittelt" -> null (kein Totalschaden). Sonst Betrag.
  const restwert = /Restwert\s+wurde\s+nicht\s+ermittelt/i.test(t)
    ? null
    : firstNum(t, /Restwert(?:\s*\(brutto\))?\s+EUR\s+([\d.,]+)/i);

  const beurteilungMatch = t.match(/Beurteilung\s+([A-Za-zÄÖÜäöü0-9%\-\s]{3,40}?)\s+(?:Wiederbeschaffungswert|Reparaturdauer|Schadenh|EUR)/i);
  const beurteilungTxt = beurteilungMatch?.[1];
  const beurteilung: string | null = beurteilungTxt ? beurteilungTxt.trim() : null;

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
