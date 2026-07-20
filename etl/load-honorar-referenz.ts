/**
 * load-honorar-referenz.ts — importiert fixtures/honorar_referenz.csv in
 * core.dim_honorar_referenz (Honorar-Referenztabellen je Schadenstufe, netto).
 *
 * Tabellen (Spalte `tabelle`):
 *   EIGEN        = Honorartabelle des Büros (AGB)
 *   BVSK_HB_III  = BVSK-Honorarbefragung 2024, Korridor HB III (95%-Wert)
 *   BVSK_HB_V    = BVSK 2024, Korridor HB V (wert_netto=Unter-, wert_netto_max=Obergrenze)
 *   HUK          = HUK-Coburg SV-Honorartableau (Nettobetrag; enthält ab 1000 € 80 € Nebenkosten)
 *
 * Editierbar → bei Tarif-/Befragungsänderung CSV pflegen + neu deployen. Voller Sync.
 * Trenner ';'; Kopfzeile + '#'-Zeilen übersprungen; wert_netto_max leer -> NULL.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, "..", "fixtures", "honorar_referenz.csv");
const VALID = new Set(["EIGEN", "BVSK_HB_III", "BVSK_HB_V", "HUK"]);

interface Row {
  tabelle: string;
  schaden_bis: number;
  wert_netto: number;
  wert_netto_max: number | null;
}

function parseRows(csv: string): Row[] {
  const out: Row[] = [];
  for (const raw of csv.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const p = line.split(";");
    if (p.length < 3) continue;
    const tabelle = (p[0] ?? "").trim().toUpperCase();
    if (tabelle === "TABELLE" || !VALID.has(tabelle)) continue;
    const schaden_bis = Number((p[1] ?? "").trim());
    const wert_netto = Number((p[2] ?? "").trim());
    const maxRaw = (p[3] ?? "").trim();
    const wert_netto_max = maxRaw ? Number(maxRaw) : null;
    if (!Number.isFinite(schaden_bis) || !Number.isFinite(wert_netto)) continue;
    if (wert_netto_max !== null && !Number.isFinite(wert_netto_max)) continue;
    out.push({ tabelle, schaden_bis, wert_netto, wert_netto_max });
  }
  return out;
}

async function main(): Promise<void> {
  const rows = parseRows(readFileSync(FILE, "utf8"));
  const pool = makePool();
  try {
    await pool.query("BEGIN");
    await pool.query("TRUNCATE core.dim_honorar_referenz");
    for (const r of rows) {
      await pool.query(
        `INSERT INTO core.dim_honorar_referenz (tabelle, schaden_bis, wert_netto, wert_netto_max)
           VALUES ($1,$2,$3,$4)
         ON CONFLICT (tabelle, schaden_bis) DO UPDATE
           SET wert_netto = EXCLUDED.wert_netto, wert_netto_max = EXCLUDED.wert_netto_max`,
        [r.tabelle, r.schaden_bis, r.wert_netto, r.wert_netto_max],
      );
    }
    await pool.query("COMMIT");
    console.log(`Honorar-Referenz geladen: ${rows.length} Zeilen`);
  } catch (err) {
    await pool.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
