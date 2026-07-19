/**
 * load-plz-geo.ts — spiegelt fixtures/plz4_geo.json in core.dim_plz_geo
 * (Centroid je 4-stelligem PLZ-Gebiet; Referenz-Geodaten, kein Personenbezug).
 *
 * Läuft bei jedem Deploy. Voller Sync in einer Transaktion (TRUNCATE + Bulk-Insert
 * per unnest), damit die Datei maßgeblich bleibt. Quelle: WZB plz_geocoord
 * (public domain), aggregiert auf 4 Stellen.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { makePool } from "../db.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FILE = resolve(__dirname, "..", "..", "fixtures", "plz4_geo.json");

interface Centroid {
  plz4: string;
  lat: number;
  lon: number;
  n_plz5?: number;
}

async function main(): Promise<void> {
  const { centroids } = JSON.parse(readFileSync(FILE, "utf8")) as { centroids: Centroid[] };
  const pool = makePool();
  try {
    await pool.query("BEGIN");
    await pool.query("TRUNCATE core.dim_plz_geo");
    // Bulk-Insert per unnest (ein Statement statt 3000+ Round-Trips).
    await pool.query(
      `INSERT INTO core.dim_plz_geo (plz4, lat, lon, n_plz5)
         SELECT * FROM unnest($1::text[], $2::float8[], $3::float8[], $4::int[])`,
      [
        centroids.map((c) => c.plz4),
        centroids.map((c) => c.lat),
        centroids.map((c) => c.lon),
        centroids.map((c) => c.n_plz5 ?? null),
      ],
    );
    await pool.query("COMMIT");
    console.log(`PLZ-Centroide geladen: ${centroids.length}`);
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
