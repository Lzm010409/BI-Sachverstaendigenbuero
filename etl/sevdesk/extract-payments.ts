/**
 * extract-payments.ts — Zahlungs-/Ausbuchungsbuchungen je sevDesk-Rechnung nach
 * raw.sevdesk_invoice_bookings.
 *
 * Läuft NACH extract-invoices.ts: iteriert über die geladenen Rechnungs-IDs und
 * holt je Rechnung die Buchungen via `Invoice/{id}/getCheckAccountTransactionLogs`.
 * `embed=checkAccountTransaction,checkAccountTransaction.checkAccount` liefert
 * Betrag, Datum und Konto (Postbank vs. „Ausgebuchte Rechnungen") in einem Call.
 *
 * DSGVO Option A: projectBooking() persistiert nur Betrag/Datum/Konto/IDs — kein
 * payeePayerName/IBAN/Verwendungszweck. Idempotenter Upsert per Log-Objekt-ID.
 */
import { makePool } from "../db.js";
import { paginate } from "./client.js";
import { projectBooking } from "./project.js";
import { logRun } from "./run-log.js";

const SOURCE = "sevdesk_invoice_bookings";

interface Log {
  id: number | string;
  [k: string]: unknown;
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const invoices = await pool.query<{ id: string }>(
      "SELECT id FROM raw.sevdesk_invoices ORDER BY id",
    );
    console.log(`Extrahiere Zahlungsbuchungen für ${invoices.rowCount} Rechnungen …`);

    let total = 0;
    for (const { id } of invoices.rows) {
      const count = await paginate<Log>(
        `Invoice/${id}/getCheckAccountTransactionLogs`,
        { embed: "checkAccountTransaction,checkAccountTransaction.checkAccount" },
        async (log) => {
          const { id: logId, invoice_id, payload } = projectBooking(log as Record<string, unknown>);
          await pool.query(
            `INSERT INTO raw.sevdesk_invoice_bookings (id, invoice_id, payload, extracted_at)
               VALUES ($1, $2, $3, now())
             ON CONFLICT (id) DO UPDATE
               SET invoice_id = EXCLUDED.invoice_id,
                   payload = EXCLUDED.payload,
                   extracted_at = now()`,
            [Number(logId), Number(invoice_id || id), payload],
          );
        },
      );
      total += count;
    }

    await pool.query(
      `INSERT INTO raw._sync_state (source, last_run)
         VALUES ($1, now())
       ON CONFLICT (source) DO UPDATE SET last_run = now()`,
      [SOURCE],
    );

    await logRun(pool, SOURCE, "ok", total, null);
    console.log(`Fertig: ${total} Buchungen aktualisiert.`);
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
