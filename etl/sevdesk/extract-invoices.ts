/**
 * extract-invoices.ts — sevDesk-Rechnungen (Kopf) nach raw.sevdesk_invoices.
 *
 * - DSGVO Option A: vor dem Schreiben wird per projectInvoice() auf ein
 *   personenbezugsfreies Whitelist-Projekt reduziert (kein contact, keine Adresse,
 *   keine Freitexte).
 * - Belastbar ab 2024 (SEVDESK_SINCE, Default 2024-01-01) — sevDesk filtert per
 *   `startDate` (Unix-Sekunden) auf das Rechnungsdatum.
 * - Idempotenter Upsert per Objekt-ID. Voller Abzug je Lauf (Volumen klein);
 *   ein Änderungs-Wasserstand wird informativ in raw._sync_state gepflegt.
 *
 * Positionen holt der separate Extraktor extract-positions.ts nach.
 */
import { makePool } from "../db.js";
import { paginate } from "./client.js";
import { projectInvoice } from "./project.js";

const SOURCE = "sevdesk_invoices";

interface Invoice {
  id: number | string;
  update?: string;
  [k: string]: unknown;
}

function sinceUnix(): number {
  const iso = process.env.SEVDESK_SINCE ?? "2024-01-01";
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) throw new Error(`SEVDESK_SINCE ungültig: ${iso}`);
  return Math.floor(ms / 1000);
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const params: Record<string, string> = { startDate: String(sinceUnix()) };
    console.log(`Extrahiere sevDesk-Rechnungen ab ${process.env.SEVDESK_SINCE ?? "2024-01-01"} …`);

    let maxUpdate: string | null = null;
    const count = await paginate<Invoice>("Invoice", params, async (inv) => {
      const payload = projectInvoice(inv as Record<string, unknown>);
      await pool.query(
        `INSERT INTO raw.sevdesk_invoices (id, payload, extracted_at)
           VALUES ($1, $2, now())
         ON CONFLICT (id) DO UPDATE
           SET payload = EXCLUDED.payload, extracted_at = now()`,
        [Number(inv.id), payload],
      );
      const u = typeof inv.update === "string" ? inv.update : null;
      if (u && (maxUpdate === null || u > maxUpdate)) maxUpdate = u;
    });

    await pool.query(
      `INSERT INTO raw._sync_state (source, last_updated_ts, last_run)
         VALUES ($1, $2, now())
       ON CONFLICT (source) DO UPDATE
         SET last_updated_ts = GREATEST(
               raw._sync_state.last_updated_ts, EXCLUDED.last_updated_ts),
             last_run = now()`,
      [SOURCE, maxUpdate],
    );

    console.log(`Fertig: ${count} Rechnungen aktualisiert.`);
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
