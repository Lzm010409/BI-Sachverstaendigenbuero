/**
 * extract-positions.ts — sevDesk-Rechnungspositionen nach
 * raw.sevdesk_invoice_positions.
 *
 * Läuft NACH extract-invoices.ts: iteriert über die bereits geladenen Rechnungs-
 * IDs und holt je Rechnung die Positionen via `Invoice/{id}/getPositions`.
 * `embed=part,unity` liefert Teil-/Einheit-Details (Kategorie-Signal) in einem Call.
 *
 * DSGVO Option A: projectPosition() verwirft den (eingebetteten) invoice-Block bis
 * auf dessen id und den Freitext `text` (Kennzeichen-/Namensrisiko).
 * Idempotenter Upsert per Positions-Objekt-ID.
 */
import { makePool } from "../db.js";
import { paginate, SevdeskHttpError } from "./client.js";
import { projectPosition } from "./project.js";
import { logRun } from "./run-log.js";

interface Position {
  id: number | string;
  [k: string]: unknown;
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const invoices = await pool.query<{ id: string }>(
      "SELECT id FROM raw.sevdesk_invoices ORDER BY id",
    );
    console.log(`Extrahiere Positionen für ${invoices.rowCount} Rechnungen …`);

    let total = 0;
    let skipped = 0;
    for (const { id } of invoices.rows) {
      try {
        const count = await paginate<Position>(
          `Invoice/${id}/getPositions`,
          { embed: "part,unity" },
          async (pos) => {
            const { id: posId, invoice_id, payload } = projectPosition(pos as Record<string, unknown>);
            await pool.query(
              `INSERT INTO raw.sevdesk_invoice_positions (id, invoice_id, payload, extracted_at)
                 VALUES ($1, $2, $3, now())
               ON CONFLICT (id) DO UPDATE
                 SET invoice_id = EXCLUDED.invoice_id,
                     payload = EXCLUDED.payload,
                     extracted_at = now()`,
              [Number(posId), Number(invoice_id || id), payload],
            );
          },
        );
        total += count;
      } catch (err) {
        // Nachträglich in sevDesk gelöschte Rechnung (ID bleibt in raw) -> 404.
        // Überspringen statt Abbruch; andere Fehler bleiben fatal.
        if (err instanceof SevdeskHttpError && err.status === 404) {
          skipped++;
          continue;
        }
        throw err;
      }
    }

    await logRun(pool, "sevdesk_invoice_positions", "ok", total, skipped ? `skipped_404=${skipped}` : null);
    console.log(
      `Fertig: ${total} Positionen aktualisiert${skipped ? `, ${skipped} gelöschte Rechnung(en) übersprungen (404)` : ""}.`,
    );
  } catch (err) {
    await logRun(pool, "sevdesk_invoice_positions", "error", null, err instanceof Error ? err.message : String(err));
    throw err;
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
