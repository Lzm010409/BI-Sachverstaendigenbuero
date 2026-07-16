/**
 * server.ts — kleiner HTTP-Ingest-Dienst für n8n → Warehouse.
 *
 * n8n und die Warehouse-DB sind NICHT im selben Netz — n8n kann Postgres nicht
 * direkt erreichen. Dieser Dienst läuft dagegen im Coolify-/Warehouse-Netz (wie der
 * ETL-Container) und nimmt die von n8n extrahierten Datensätze per HTTP entgegen,
 * validiert minimal und upsertet sie in `raw`. n8n spricht ihn über eine öffentliche
 * Coolify-Domain (Reverse Proxy) mit Bearer-Token an.
 *
 * Auth: `Authorization: Bearer $INGEST_TOKEN`. Ohne gesetztes Token startet der
 * Dienst NICHT (fail-closed). Nur POST auf die Ingest-Routen, GET /health.
 *
 * DSGVO: der Dienst schreibt nur, was n8n schickt — die Extraktoren liefern
 * ausschließlich Fachwerte/Fakten (kein Freitext, kein Personenbezug).
 */
import http from "node:http";
import { makePool } from "../db.js";

const TOKEN = process.env.INGEST_TOKEN;
if (!TOKEN) {
  console.error("Fehlt: Umgebungsvariable INGEST_TOKEN — Dienst startet nicht.");
  process.exit(1);
}
const PORT = Number(process.env.INGEST_PORT ?? 8080);
const pool = makePool();

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > 1_000_000) { reject(new Error("Body zu groß")); req.destroy(); return; }
      data += c;
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function send(res: http.ServerResponse, code: number, obj: unknown): void {
  const body = JSON.stringify(obj);
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") { send(res, 200, { ok: true }); return; }
    if (req.headers["authorization"] !== `Bearer ${TOKEN}`) { send(res, 401, { error: "unauthorized" }); return; }

    // Arbeitsliste für den Phase-4-Workflow: geschlossene Fälle ohne Fachwerte.
    // n8n kann die DB nicht lesen — daher hier als HTTP-GET bereitgestellt.
    if (req.method === "GET" && req.url === "/pending/gutachten") {
      const { rows } = await pool.query(
        `SELECT az AS aktenzeichen, replace(az,'/','_') AS ordner,
                '20'||substring(az from 3 for 2) AS jahr, substring(az from 1 for 2) AS monat
           FROM (SELECT upper(regexp_replace(payload->>'title','\\s','','g')) AS az,
                        payload->>'status' AS status FROM raw.pipedrive_deals) d
          WHERE d.status='won' AND d.az ~ '^[0-9]{4}/[0-9]+TG$'
            AND NOT EXISTS (SELECT 1 FROM raw.gutachten_fachwerte f WHERE f.aktenzeichen = d.az)
          LIMIT 50`,
      );
      send(res, 200, rows); return;
    }

    if (req.method !== "POST") { send(res, 405, { error: "method not allowed" }); return; }

    const body = JSON.parse(await readBody(req)) as Record<string, unknown>;

    if (req.url === "/ingest/gutachten") {
      // { aktenzeichen, payload, quelle_datei }
      const az = body.aktenzeichen;
      if (typeof az !== "string" || !az || body.payload == null) { send(res, 400, { error: "aktenzeichen + payload nötig" }); return; }
      await pool.query(
        `INSERT INTO raw.gutachten_fachwerte (aktenzeichen, payload, quelle_datei, extracted_at)
           VALUES ($1, $2, $3, now())
         ON CONFLICT (aktenzeichen) DO UPDATE
           SET payload = EXCLUDED.payload, quelle_datei = EXCLUDED.quelle_datei, extracted_at = now()`,
        [az, body.payload, (body.quelle_datei as string) ?? null],
      );
      send(res, 200, { ok: true, aktenzeichen: az }); return;
    }

    if (req.url === "/ingest/kuerzung") {
      // { letter_key, aktenzeichen, payload, quelle }
      const key = body.letter_key;
      if (typeof key !== "string" || !key || body.payload == null) { send(res, 400, { error: "letter_key + payload nötig" }); return; }
      await pool.query(
        `INSERT INTO raw.kuerzungsschreiben (letter_key, aktenzeichen, payload, quelle, extracted_at)
           VALUES ($1, $2, $3, $4, now())
         ON CONFLICT (letter_key) DO UPDATE
           SET aktenzeichen = EXCLUDED.aktenzeichen, payload = EXCLUDED.payload,
               quelle = EXCLUDED.quelle, extracted_at = now()`,
        [key, (body.aktenzeichen as string) ?? null, body.payload, (body.quelle as string) ?? null],
      );
      send(res, 200, { ok: true, letter_key: key }); return;
    }

    send(res, 404, { error: "not found" });
  } catch (err) {
    send(res, 500, { error: (err instanceof Error ? err.message : String(err)).slice(0, 200) });
  }
});

server.listen(PORT, () => console.log(`Ingest-Dienst auf :${PORT} (POST /ingest/gutachten, /ingest/kuerzung)`));
