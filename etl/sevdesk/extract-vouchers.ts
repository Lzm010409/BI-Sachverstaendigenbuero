/**
 * extract-vouchers.ts — sevDesk-Belege (Voucher) nach raw.sevdesk_vouchers.
 *
 * Ziel Phase 5: die „Forderungsverlust <Aktenzeichen>"-Belege = die tatsächliche
 * Ausbuchung je Fall. sevDesk bietet für /Voucher nur limit/offset (kein
 * Server-Filter auf description) — daher voller Abzug ab SEVDESK_SINCE und
 * clientseitiger Filter auf den Belegtitel.
 *
 * - DSGVO Option A: projectVoucher() verwirft supplier/supplierName + Kontaktdaten
 *   vor dem Schreiben. description (Belegtitel inkl. Aktenzeichen) bleibt.
 * - Aktenzeichen aus der description extrahiert (Format MMJJ/NummerTG), normalisiert.
 * - Idempotenter Upsert per Voucher-ID.
 */
import { makePool } from "../db.js";
import { paginate } from "./client.js";
import { projectVoucher } from "./project.js";
import { logRun } from "./run-log.js";

const SOURCE = "sevdesk_vouchers";

// Nur Forderungsverlust-Belege sind für die Ausbuchung relevant.
const TITEL_RE = /forderungsverlust/i;
const AZ_RE = /\d{4}\/\d+TG/;

interface Voucher {
  id: number | string;
  description?: string;
  update?: string;
  [k: string]: unknown;
}

function sinceUnix(): number {
  const iso = process.env.SEVDESK_SINCE ?? "2024-01-01";
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) throw new Error(`SEVDESK_SINCE ungültig: ${iso}`);
  return Math.floor(ms / 1000);
}

/** Aktenzeichen aus dem Belegtitel ziehen (normalisiert: Großschrift, ohne Space). */
function aktenzeichenAus(description: string | undefined): string | null {
  if (!description) return null;
  const norm = description.toUpperCase().replace(/\s/g, "");
  const m = norm.match(AZ_RE);
  return m ? m[0] : null;
}

async function main(): Promise<void> {
  const pool = makePool();
  try {
    const params: Record<string, string> = { startDate: String(sinceUnix()) };
    console.log(`Extrahiere sevDesk-Forderungsverlust-Belege ab ${process.env.SEVDESK_SINCE ?? "2024-01-01"} …`);

    let count = 0;
    let maxUpdate: string | null = null;
    await paginate<Voucher>("Voucher", params, async (v) => {
      const desc = typeof v.description === "string" ? v.description : undefined;
      if (!desc || !TITEL_RE.test(desc)) return; // nur Forderungsverlust-Belege
      const payload = projectVoucher(v as Record<string, unknown>);
      await pool.query(
        `INSERT INTO raw.sevdesk_vouchers (id, aktenzeichen, payload, extracted_at)
           VALUES ($1, $2, $3, now())
         ON CONFLICT (id) DO UPDATE
           SET aktenzeichen = EXCLUDED.aktenzeichen,
               payload      = EXCLUDED.payload,
               extracted_at = now()`,
        [Number(v.id), aktenzeichenAus(desc), payload],
      );
      count++;
      const u = typeof v.update === "string" ? v.update : null;
      if (u && (maxUpdate === null || u > maxUpdate)) maxUpdate = u;
    });

    await pool.query(
      `INSERT INTO raw._sync_state (source, last_updated_ts, last_run)
         VALUES ($1, $2, now())
       ON CONFLICT (source) DO UPDATE
         SET last_updated_ts = GREATEST(raw._sync_state.last_updated_ts, EXCLUDED.last_updated_ts),
             last_run = now()`,
      [SOURCE, maxUpdate],
    );

    await logRun(pool, SOURCE, "ok", count, null);
    console.log(`Fertig: ${count} Forderungsverlust-Belege aktualisiert.`);
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
