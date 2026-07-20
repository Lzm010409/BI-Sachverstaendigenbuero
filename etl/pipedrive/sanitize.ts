/**
 * sanitize.ts — entfernt aus Pipedrive-Payloads AUSSCHLIESSLICH die Zeichen, die
 * PostgreSQL physisch nicht in `jsonb`/`text` speichern kann. Ohne diesen Schritt
 * kippt der komplette Extraktionslauf, sobald EIN Datensatz ein solches Zeichen
 * enthaelt (real ab 15.07.: `pipedrive_deals`/`_organizations` blieben stehen,
 * waehrend `pipedrive_person_geo` weiterlief — letzterer speichert nur extrahierte
 * Skalare, keinen Voll-Payload).
 *
 * Verhaeltnis zu "Rohdaten sind heilig": Es gibt keine speicherbare Variante von
 * U+0000 in einem Postgres-Wert — die Alternative waere, den Datensatz GAR NICHT
 * zu speichern. Wir entfernen daher nur das NUL-Zeichen und reparieren einzelne
 * (verwaiste) UTF-16-Surrogate zu U+FFFD. Alle anderen Zeichen — auch sonstige
 * Steuerzeichen U+0001..U+001F, die jsonb akzeptiert — bleiben unveraendert.
 */

const NUL = /\u0000/g;
const LONE_HIGH = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])/g;
const LONE_LOW = /(^|[^\uD800-\uDBFF])([\uDC00-\uDFFF])/g;
const REPLACEMENT = "\uFFFD";

/** Ersetzt NUL und verwaiste Surrogate in EINEM String. */
function cleanString(s: string): string {
  let out = s.replace(NUL, "");
  out = out.replace(LONE_HIGH, REPLACEMENT);
  out = out.replace(LONE_LOW, (_m, p) => p + REPLACEMENT);
  return out;
}

/**
 * Bereinigt ein Objekt/Array/Skalar rekursiv. Gibt den (ggf. neuen) Wert zurueck
 * und meldet ueber das ref-Objekt, ob ueberhaupt etwas geaendert wurde — fuer
 * Observability, damit im Log sichtbar ist, dass/ob bereinigt wurde.
 */
function walk(value: unknown, ref: { changed: boolean }): unknown {
  if (typeof value === "string") {
    const c = cleanString(value);
    if (c !== value) ref.changed = true;
    return c;
  }
  if (Array.isArray(value)) return value.map((v) => walk(v, ref));
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      const ck = cleanString(k);
      if (ck !== k) ref.changed = true;
      out[ck] = walk(v, ref);
    }
    return out;
  }
  return value;
}

/**
 * Liefert eine fuer jsonb speicherbare Kopie von `payload` plus ein `changed`-Flag.
 * Enthaelt der Payload keine problematischen Zeichen, ist `changed=false` und der
 * Inhalt bleibt inhaltsgleich (unveraenderte Kopie).
 */
export function sanitizeForJsonb<T>(payload: T): { value: T; changed: boolean } {
  const ref = { changed: false };
  const value = walk(payload, ref) as T;
  return { value, changed: ref.changed };
}
