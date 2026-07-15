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
import { paginate } from "./client.js";
import { projectPosition } from "./project.js";

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
    for (const { id } of invoices.rows) {
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
    }

    console.log(`Fertig: ${total} Positionen aktualisiert.`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
