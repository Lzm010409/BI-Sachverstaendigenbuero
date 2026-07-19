/**
 * extract-fachwerte.ts — LAUFENDER Gutachten-Feed (löst den Einmal-Backfill ab).
 *
 * Pipeline je Fall (headless im Coolify-etl-Container):
 *   Deal (Pipedrive-Custom-Field AUTOIXPERT_GUTACHTEN_ID) -> report_id
 *   -> fetchGutachtenPdf (autoiXpert externalApi, documents/download)
 *   -> pdfToText -> parseFachwerte -> Upsert raw.gutachten_fachwerte
 *
 * Inkrementell & schonend:
 *   - Arbeitsliste = Deals mit Gutachten-ID, deren Aktenzeichen NOCH NICHT in
 *     raw.gutachten_fachwerte steht UND die nicht kürzlich (< 21 Tage) erfolglos
 *     versucht wurden (raw.gutachten_fetch_log). So werden Fälle ohne abgelegtes
 *     Gutachten nicht bei jedem Deploy neu abgefragt.
 *   - Obergrenze je Lauf (BATCH) hält Deploy-Zeit/Last im Rahmen; Rest kommt beim
 *     nächsten Lauf. Was ausgelassen wurde, wird geloggt (kein stilles Kappen).
 *   - Jeder Fall in try/catch — ein kaputtes PDF kippt nie den ganzen Lauf.
 *
 * SICHERHEITSGATE: ohne AUTOIXPERT_API_TOKEN passiert NICHTS (Skip, exit 0) — gefahrlos
 * in der Deploy-Kette. DSGVO: parseFachwerte liefert NUR die 9 numerischen Fachwerte +
 * Klassifikation; der restliche PDF-Text (VIN/Kennzeichen/Klarname) wird nie persistiert.
 */
import { makePool } from "../db.js";
import { DEAL_FIELDS } from "../pipedrive/fields.generated.js";
import { fetchGutachtenPdf } from "./fetch-pdf.js";
import { pdfToText } from "./pdf-text.js";
import { parseFachwerte } from "./parse-fachwerte.js";

const SOURCE = "gutachten_fachwerte";
const BATCH = Number(process.env.GUTACHTEN_BATCH ?? "150");

interface Aufgabe {
  aktenzeichen: string;
  report_id: string;
}

async function main(): Promise<void> {
  if (!process.env.AUTOIXPERT_API_TOKEN) {
    console.log("AUTOIXPERT_API_TOKEN nicht gesetzt — überspringe Gutachten-Feed.");
    return;
  }
  const pool = makePool();
  try {
    const { rows } = await pool.query<Aufgabe>(
      `SELECT DISTINCT ON (aktenzeichen) aktenzeichen, report_id FROM (
         SELECT upper(regexp_replace(d.payload->>'title','\\s','','g'))        AS aktenzeichen,
                nullif(trim(d.payload->'custom_fields'->>$1),'')                AS report_id
           FROM raw.pipedrive_deals d
          WHERE nullif(trim(d.payload->'custom_fields'->>$1),'') IS NOT NULL
            AND upper(regexp_replace(d.payload->>'title','\\s','','g')) ~ '^\\d{4}/\\d+TG$'
       ) q
       WHERE aktenzeichen NOT IN (SELECT aktenzeichen FROM raw.gutachten_fachwerte)
         AND aktenzeichen NOT IN (
               SELECT aktenzeichen FROM raw.gutachten_fetch_log
                WHERE status <> 'ok' AND attempted_at > now() - INTERVAL '21 days')
       ORDER BY aktenzeichen`,
      [DEAL_FIELDS.AUTOIXPERT_GUTACHTEN_ID],
    );

    const gesamt = rows.length;
    const arbeit = rows.slice(0, BATCH);
    if (gesamt > BATCH) {
      console.log(`Gutachten-Feed: ${gesamt} offen, verarbeite ${BATCH} in diesem Lauf (Rest folgt).`);
    } else {
      console.log(`Gutachten-Feed: ${gesamt} offene Fälle.`);
    }

    let ok = 0, kein_dok = 0, kein_wert = 0, fehler = 0;
    for (const a of arbeit) {
      try {
        const res = await fetchGutachtenPdf(a.report_id);
        if (res.status !== "ok" || !res.pdf) {
          await logAttempt(pool, a, res.status, res.note ?? null);
          kein_dok++;
          continue;
        }
        const text = await pdfToText(res.pdf);
        const fw = parseFachwerte(text, a.aktenzeichen);
        // Nur speichern, wenn wenigstens EIN Fachwert/Klassifikation erkannt wurde.
        const hatWert = fw.beurteilung != null || fw.wiederbeschaffungswert != null ||
                        fw.reparaturkosten_brutto != null || fw.schadenhoehe_brutto != null;
        if (!hatWert) {
          await logAttempt(pool, a, "kein_wert", `Doc ${res.docType ?? "?"} geparst, keine Fachwerte`);
          kein_wert++;
          continue;
        }
        const payload = {
          wiederbeschaffungswert: fw.wiederbeschaffungswert,
          restwert: fw.restwert,
          wertminderung: fw.wertminderung,
          reparaturkosten_netto: fw.reparaturkosten_netto,
          reparaturkosten_brutto: fw.reparaturkosten_brutto,
          schadenhoehe_brutto: fw.schadenhoehe_brutto,
          nutzungsausfall_tagessatz: fw.nutzungsausfall_tagessatz,
          reparaturdauer_tage: fw.reparaturdauer_tage,
          beurteilung: fw.beurteilung,
        };
        await pool.query(
          `INSERT INTO raw.gutachten_fachwerte (aktenzeichen, payload, quelle_datei, extracted_at)
             VALUES ($1, $2, $3, now())
           ON CONFLICT (aktenzeichen) DO UPDATE
             SET payload = EXCLUDED.payload, quelle_datei = EXCLUDED.quelle_datei, extracted_at = now()`,
          [a.aktenzeichen, JSON.stringify(payload), `autoixpert:${a.report_id} (${res.docType ?? "?"})`],
        );
        await logAttempt(pool, a, "ok", res.docType ?? null);
        ok++;
      } catch (err) {
        await logAttempt(pool, a, "fehler", err instanceof Error ? err.message.slice(0, 200) : String(err));
        fehler++;
      }
    }

    // Wasserstand nur als Lauf-Marke (die Arbeitsliste ist selbst-inkrementell).
    await pool.query(
      `INSERT INTO raw._sync_state (source, last_updated_ts, last_run)
         VALUES ($1, now(), now())
       ON CONFLICT (source) DO UPDATE SET last_updated_ts = now(), last_run = now()`,
      [SOURCE],
    );
    console.log(`Gutachten-Feed fertig: ${ok} neu, ${kein_dok} ohne Dokument, ${kein_wert} ohne Fachwerte, ${fehler} Fehler.`);
  } finally {
    await pool.end();
  }
}

async function logAttempt(
  pool: ReturnType<typeof makePool>, a: Aufgabe, status: string, note: string | null,
): Promise<void> {
  await pool.query(
    `INSERT INTO raw.gutachten_fetch_log (aktenzeichen, report_id, status, note, attempted_at)
       VALUES ($1, $2, $3, $4, now())
     ON CONFLICT (aktenzeichen) DO UPDATE
       SET report_id = EXCLUDED.report_id, status = EXCLUDED.status,
           note = EXCLUDED.note, attempted_at = now()`,
    [a.aktenzeichen, a.report_id, status, note],
  );
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
