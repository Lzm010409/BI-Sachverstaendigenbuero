/**
 * extract-persons.ts — DSGVO-GEFILTERTE Personen-Geodaten nach
 * raw.pipedrive_person_geo (für die Einzugsgebiet-Dimension, Leitfrage 7).
 *
 * ABWEICHUNG von "raw ist unverändert": Personen tragen Klarnamen, Straße,
 * Telefon, E-Mail. NICHTS davon wird gespeichert. Aus dem vollen Payload wird
 * AUSSCHLIESSLICH extrahiert:
 *   - plz_gebiet: die ERSTEN 2 ZIFFERN der Wohn-PLZ (PLZ-Gebiet, datensparsam;
 *     nie die 5-stellige PLZ),
 *   - ort:        der Wohnort (Stadt) — Einzugsgebiet-Kennzahl.
 * Der Join zum Fall läuft über deal.person_id (raw.pipedrive_deals). Der
 * person_id ist ein pseudonymer Schlüssel; ohne Namen bleibt der Bezug
 * pseudonymisiert.
 *
 * Feldzugriff nur über PERSON_FIELDS (fields.generated.ts), nie über rohe Hashes.
 * Wasserstand in raw._sync_state (source='pipedrive_person_geo').
 */
import { makePool } from "../db.js";
import { paginate } from "./client.js";
import { PERSON_FIELDS } from "./fields.generated.js";

const SOURCE = "pipedrive_person_geo";

interface Person {
  id: number;
  update_time?: string;
  custom_fields?: Record<string, unknown> | null;
  [k: string]: unknown;
}

/** PLZ -> PLZ-Gebiet (erste 2 Ziffern). Nie die volle PLZ zurückgeben. */
function toPlzGebiet(raw: unknown): string | null {
  if (raw == null) return null;
  const digits = String(raw).replace(/\D/g, "");
  return digits.length >= 2 ? digits.slice(0, 2) : null;
}

/**
 * PLZ -> 4-stelliges PLZ-Gebiet. Vom Inhaber freigegeben (feineres Einzugsgebiet,
 * LF7): 4 von 5 Ziffern bleiben Gebiet, nie die volle 5-stellige PLZ, keine Adresse.
 * Auswertungen aggregieren zusätzlich mit Mindestfallzahl.
 */
function toPlz4(raw: unknown): string | null {
  if (raw == null) return null;
  const digits = String(raw).replace(/\D/g, "");
  return digits.length >= 4 ? digits.slice(0, 4) : null;
}

function toOrt(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const t = raw.trim();
  return t.length ? t : null;
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const wm = await pool.query<{ last_updated_ts: string | null }>(
      "SELECT last_updated_ts FROM raw._sync_state WHERE source = $1",
      [SOURCE],
    );
    const since = wm.rows[0]?.last_updated_ts ?? null;

    const params: Record<string, string> = {
      sort_by: "update_time",
      sort_direction: "asc",
    };
    if (since) params.updated_since = new Date(since).toISOString();

    console.log(
      `Extrahiere Personen-Geodaten${since ? ` seit ${params.updated_since}` : " (voll)"} …`,
    );

    const { count, maxUpdateTime } = await paginate<Person>(
      "persons",
      params,
      async (person) => {
        const cf = person.custom_fields ?? {};
        const plzGebiet = toPlzGebiet(cf[PERSON_FIELDS.PLZ]);
        const plz4 = toPlz4(cf[PERSON_FIELDS.PLZ]);
        const ort = toOrt(cf[PERSON_FIELDS.ORT]);
        // Nur die PII-armen Geo-Felder (Gebiet/Ort) — niemals Name/Straße/Kontakt
        // und nie die volle 5-stellige PLZ.
        await pool.query(
          `INSERT INTO raw.pipedrive_person_geo (person_id, plz_gebiet, plz4, ort, extracted_at)
             VALUES ($1, $2, $3, $4, now())
           ON CONFLICT (person_id) DO UPDATE
             SET plz_gebiet = EXCLUDED.plz_gebiet, plz4 = EXCLUDED.plz4,
                 ort = EXCLUDED.ort, extracted_at = now()`,
          [person.id, plzGebiet, plz4, ort],
        );
      },
    );

    const newWm = maxUpdateTime ?? since;
    await pool.query(
      `INSERT INTO raw._sync_state (source, last_updated_ts, last_run)
         VALUES ($1, $2, now())
       ON CONFLICT (source) DO UPDATE
         SET last_updated_ts = GREATEST(
               raw._sync_state.last_updated_ts, EXCLUDED.last_updated_ts),
             last_run = now()`,
      [SOURCE, newWm],
    );

    console.log(`Fertig: ${count} Personen-Geodaten. Wasserstand: ${newWm ?? "—"}`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
