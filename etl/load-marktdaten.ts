/**
 * load-marktdaten.ts — importiert die Marktdaten-Fixtures für die Expansions-Analyse:
 *   fixtures/markt_kreis.csv  -> core.dim_markt_kreis  (Kreis + amtliche Marktkennzahlen)
 *   fixtures/plz4_kreis.csv   -> core.dim_plz4_kreis   (PLZ4 -> Kreis, Brücke zum Bestand)
 *
 * Marktkennzahlen (einwohner/kfz_bestand/unfaelle_gesamt) sind amtlich zu befüllen
 * (KBA FZ1, IT.NRW/Destatis) und bleiben sonst NULL — nie schätzen (CLAUDE.md).
 *
 * Editierbar -> bei neuen Jahreszahlen / Zuordnungen CSV pflegen + neu deployen.
 * Trenner ';'; Kopfzeile + '#'-Zeilen übersprungen; leere Felder -> NULL. Voller Sync.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "./db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const F_KREIS = resolve(__dirname, "..", "fixtures", "markt_kreis.csv");
const F_PLZ4 = resolve(__dirname, "..", "fixtures", "plz4_kreis.csv");

interface KreisRow {
  ags: string;
  kreis: string;
  bundesland: string | null;
  einwohner: number | null;
  kfz_bestand: number | null;
  unfaelle_gesamt: number | null;
  jahr: number | null;
  quelle: string | null;
}
interface Plz4Row {
  plz4: string;
  ags: string;
}

function cells(csv: string): string[][] {
  const rows: string[][] = [];
  for (const raw of csv.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    rows.push(line.split(";"));
  }
  return rows;
}

function num(s: string | undefined): number | null {
  const v = (s ?? "").trim();
  if (!v) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
function str(s: string | undefined): string | null {
  const v = (s ?? "").trim();
  return v ? v : null;
}

function parseKreis(csv: string): KreisRow[] {
  const out: KreisRow[] = [];
  for (const p of cells(csv)) {
    const ags = (p[0] ?? "").trim();
    if (ags.toLowerCase() === "ags") continue;
    const kreis = (p[1] ?? "").trim();
    if (!ags || !kreis) continue;
    out.push({
      ags,
      kreis,
      bundesland: str(p[2]),
      einwohner: num(p[3]),
      kfz_bestand: num(p[4]),
      unfaelle_gesamt: num(p[5]),
      jahr: num(p[6]),
      quelle: str(p[7]),
    });
  }
  return out;
}

function parsePlz4(csv: string): Plz4Row[] {
  const out: Plz4Row[] = [];
  for (const p of cells(csv)) {
    const plz4 = (p[0] ?? "").trim();
    if (plz4.toLowerCase() === "plz4") continue;
    const ags = (p[1] ?? "").trim();
    if (!plz4 || !ags) continue;
    out.push({ plz4, ags });
  }
  return out;
}

async function main(): Promise<void> {
  const kreise = parseKreis(readFileSync(F_KREIS, "utf8"));
  const plz4 = parsePlz4(readFileSync(F_PLZ4, "utf8"));
  const valid = new Set(kreise.map((k) => k.ags));
  const orphan = plz4.filter((p) => !valid.has(p.ags));
  if (orphan.length) {
    throw new Error(
      `plz4_kreis.csv verweist auf unbekannte ags: ${orphan.map((o) => o.plz4 + "->" + o.ags).join(", ")}`,
    );
  }

  const pool = makePool();
  try {
    await pool.query("BEGIN");
    // Kind zuerst leeren (FK-frei, aber Reihenfolge sauber halten), dann Eltern.
    await pool.query("TRUNCATE core.dim_plz4_kreis");
    await pool.query("TRUNCATE core.dim_markt_kreis");
    for (const k of kreise) {
      await pool.query(
        `INSERT INTO core.dim_markt_kreis
           (ags, kreis, bundesland, einwohner, kfz_bestand, unfaelle_gesamt, jahr, quelle)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [k.ags, k.kreis, k.bundesland, k.einwohner, k.kfz_bestand, k.unfaelle_gesamt, k.jahr, k.quelle],
      );
    }
    for (const p of plz4) {
      await pool.query(
        `INSERT INTO core.dim_plz4_kreis (plz4, ags) VALUES ($1,$2)`,
        [p.plz4, p.ags],
      );
    }
    await pool.query("COMMIT");
    const mitWerten = kreise.filter((k) => k.kfz_bestand != null || k.einwohner != null).length;
    console.log(
      `Marktdaten geladen: ${kreise.length} Kreise (${mitWerten} mit Marktkennzahlen), ${plz4.length} PLZ4-Zuordnungen`,
    );
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
