/**
 * fetch-field-mapping.ts
 *
 * Holt die Feldmetadaten (Custom Fields inkl. Key, Label, Typ, Optionsliste)
 * autoritativ aus der Pipedrive **Fields API v2** und schreibt:
 *   - docs/field-mapping.json  (maschinenlesbar, Quelle für generate-fields.ts)
 *   - docs/field-mapping.md    (lesbare Tabelle)
 *
 * Warum v2: siehe docs/adr/0002-pipedrive-fields-api-v2.md. v2 liefert
 * Feldmetadaten mit Cursor-Pagination (limit<=500, cursor).
 *
 * Aufruf:  PIPEDRIVE_API_TOKEN=... PIPEDRIVE_COMPANY_DOMAIN=meinbuero \
 *          npm run fetch:fields
 *
 * Der Token ist read-only. Dieses Skript schreibt nie nach Pipedrive.
 */

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_DIR = resolve(__dirname, "..", "docs");

type Entity = "deal" | "person" | "organization";

interface FieldOption {
  id: number;
  label: string;
}

interface PipedriveField {
  key: string;
  name: string;
  field_type: string;
  options?: FieldOption[] | null;
  edit_flag?: boolean;
  add_visible_flag?: boolean;
  [k: string]: unknown;
}

interface MappedField {
  key: string;
  label: string;
  field_type: string;
  options: FieldOption[] | null;
}

interface FieldMapping {
  generated_at: string;
  source: "pipedrive-fields-api-v2";
  entities: Record<Entity, MappedField[]>;
}

const ENDPOINTS: Record<Entity, string> = {
  deal: "dealFields",
  person: "personFields",
  organization: "organizationFields",
};

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) {
    console.error(`Fehlt: Umgebungsvariable ${name}. Siehe .env.example.`);
    process.exit(1);
  }
  return v;
}

async function fetchAllFields(
  entity: Entity,
  baseUrl: string,
  token: string,
): Promise<MappedField[]> {
  const out: MappedField[] = [];
  let cursor: string | null = null;

  do {
    const url = new URL(`${baseUrl}/api/v2/${ENDPOINTS[entity]}`);
    url.searchParams.set("api_token", token);
    url.searchParams.set("limit", "500");
    if (cursor) url.searchParams.set("cursor", cursor);

    const res = await fetch(url, { headers: { Accept: "application/json" } });
    if (!res.ok) {
      throw new Error(
        `Pipedrive v2 ${ENDPOINTS[entity]} -> HTTP ${res.status} ${res.statusText}`,
      );
    }
    const body = (await res.json()) as {
      data?: PipedriveField[];
      additional_data?: { next_cursor?: string | null };
    };

    for (const f of body.data ?? []) {
      out.push({
        key: f.key,
        label: f.name,
        field_type: f.field_type,
        options: f.options ?? null,
      });
    }

    cursor = body.additional_data?.next_cursor ?? null;
  } while (cursor);

  return out;
}

function toMarkdown(mapping: FieldMapping): string {
  const lines: string[] = [
    "# Feldmapping (autoritativ, aus Pipedrive Fields API v2)",
    "",
    `Erzeugt: ${mapping.generated_at}`,
    "",
    "> Automatisch generiert von `scripts/fetch-field-mapping.ts`. Nicht von",
    "> Hand editieren — Änderungen gehen beim nächsten Lauf verloren.",
    "",
  ];

  for (const entity of Object.keys(mapping.entities) as Entity[]) {
    lines.push(`## ${entity}`, "");
    lines.push("| Key | Label | Typ | Optionen |");
    lines.push("|---|---|---|---|");
    for (const f of mapping.entities[entity]) {
      const opts = f.options
        ? f.options.map((o) => `${o.id}=${o.label}`).join("; ")
        : "";
      lines.push(
        `| \`${f.key}\` | ${escapeCell(f.label)} | ${f.field_type} | ${escapeCell(opts)} |`,
      );
    }
    lines.push("");
  }
  return lines.join("\n");
}

function escapeCell(s: string): string {
  return s.replace(/\|/g, "\\|").replace(/\n/g, " ");
}

async function main(): Promise<void> {
  const token = requireEnv("PIPEDRIVE_API_TOKEN");
  const domain = requireEnv("PIPEDRIVE_COMPANY_DOMAIN");
  const baseUrl = `https://${domain}.pipedrive.com`;

  const mapping: FieldMapping = {
    generated_at: new Date().toISOString(),
    source: "pipedrive-fields-api-v2",
    entities: { deal: [], person: [], organization: [] },
  };

  for (const entity of Object.keys(ENDPOINTS) as Entity[]) {
    process.stdout.write(`Hole ${entity}-Felder … `);
    mapping.entities[entity] = await fetchAllFields(entity, baseUrl, token);
    console.log(`${mapping.entities[entity].length} Felder`);
  }

  writeFileSync(
    resolve(DOCS_DIR, "field-mapping.json"),
    JSON.stringify(mapping, null, 2) + "\n",
  );
  writeFileSync(resolve(DOCS_DIR, "field-mapping.md"), toMarkdown(mapping));

  console.log(
    "Geschrieben: docs/field-mapping.json und docs/field-mapping.md.\n" +
      "Nächster Schritt: npm run generate:fields",
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
