/**
 * extract-gutachten.ts — autoiXpert-Gutachten (Fachdaten) nach raw.autoixpert_gutachten.
 *
 * Strategie (Plan §2): NICHT blind alle autoiXpert-Reports ziehen, sondern über die
 * Pipedrive-Deals mit gesetzter autoiXpert-Gutachten-ID iterieren (Feld
 * DEAL_FIELDS.AUTOIXPERT_GUTACHTEN_ID in raw.pipedrive_deals) und je ID genau EIN
 * Gutachten holen. Vorteil: nur dem Aktenzeichen zuordenbare, relevante Gutachten.
 *
 * DSGVO Option A: vor dem Schreiben reduziert projectGutachten() auf ein
 * personenbezugsfreies Whitelist-Projekt (kein VIN, kein Kennzeichen, kein Klarname,
 * keine Freitexte). Siehe project.ts.
 *
 * Idempotenter Upsert per Report-ID. `aktenzeichen` kommt vom Deal (normalisiert)
 * und wird zusätzlich als Spalte geführt; autoiXpert liefert es als `token` mit —
 * beides erlaubt Kreuzvalidierung.
 *
 * SICHERHEITSGATE: ohne AUTOIXPERT_API_TOKEN wird NICHTS getan (Skip, exit 0). Der
 * Schritt ist deshalb gefahrlos in die resiliente Deploy-Kette einzuhängen, sobald
 * der Token als Coolify-Secret gesetzt ist. Bis dahin läuft er als No-op durch.
 */
import { makePool } from "../db.js";
import { DEAL_FIELDS } from "../pipedrive/fields.generated.js";
import { fetchReport } from "./client.js";
import { projectGutachten } from "./project.js";
import { logRun } from "./run-log.js";

const SOURCE = "autoixpert_gutachten";

async function main(): Promise<void> {
  if (!process.env.AUTOIXPERT_API_TOKEN) {
    console.log("AUTOIXPERT_API_TOKEN nicht gesetzt — überspringe autoiXpert-Extraktion.");
    return;
  }

  const pool = makePool();
  try {
    // Deals mit gesetzter Gutachten-ID einsammeln (dedupliziert je Gutachten-ID).
    const { rows } = await pool.query<{ gutachten_id: string; aktenzeichen: string | null }>(
      `SELECT nullif(trim(payload -> 'custom_fields' ->> $1), '')                  AS gutachten_id,
              upper(regexp_replace(payload ->> 'title', '\\s', '', 'g'))           AS aktenzeichen
         FROM raw.pipedrive_deals
        WHERE nullif(trim(payload -> 'custom_fields' ->> $1), '') IS NOT NULL`,
      [DEAL_FIELDS.AUTOIXPERT_GUTACHTEN_ID],
    );

    const byId = new Map<string, string | null>();
    for (const r of rows) {
      if (!byId.has(r.gutachten_id)) byId.set(r.gutachten_id, r.aktenzeichen);
    }
    console.log(`Extrahiere ${byId.size} autoiXpert-Gutachten (aus ${rows.length} Deals mit Gutachten-ID) …`);

    let count = 0;
    let missing = 0;
    for (const [gutachtenId, aktenzeichen] of byId) {
      const report = await fetchReport(gutachtenId);
      if (report === null) {
        missing++;
        continue; // 404 — Gutachten-ID unbekannt/gelöscht; nicht fatal.
      }
      const payload = projectGutachten(report);
      await pool.query(
        `INSERT INTO raw.autoixpert_gutachten (id, aktenzeichen, payload, extracted_at)
           VALUES ($1, $2, $3, now())
         ON CONFLICT (id) DO UPDATE
           SET aktenzeichen = EXCLUDED.aktenzeichen,
               payload      = EXCLUDED.payload,
               extracted_at = now()`,
        [gutachtenId, aktenzeichen, payload],
      );
      count++;
    }

    await pool.query(
      `INSERT INTO raw._sync_state (source, last_updated_ts, last_run)
         VALUES ($1, now(), now())
       ON CONFLICT (source) DO UPDATE
         SET last_updated_ts = now(), last_run = now()`,
      [SOURCE],
    );

    await logRun(pool, SOURCE, "ok", count, null);
    console.log(`Fertig: ${count} Gutachten aktualisiert, ${missing} nicht gefunden (404).`);
  } catch (err) {
    await logRun(pool, SOURCE, "error", null, err instanceof Error ? err.message : String(err));
    throw err;
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
