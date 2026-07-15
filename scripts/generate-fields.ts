/**
 * generate-fields.ts
 *
 * Liest docs/field-mapping.json und erzeugt etl/pipedrive/fields.generated.ts:
 * benannte Konstanten (Hash-Key hinter sprechendem Namen), Optionslisten und
 * DSGVO-Ausschlussliste. Damit steht nirgends im Code ein roher Pipedrive-Hash.
 *
 * Aufruf:  npm run generate:fields
 *
 * Idempotent. Läuft ohne Netz; braucht nur das committete JSON.
 */

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const IN = resolve(ROOT, "docs", "field-mapping.json");
const OUT = resolve(ROOT, "etl", "pipedrive", "fields.generated.ts");

interface Field {
  key: string;
  label: string;
  field_type: string;
  options: { id: number; label: string }[] | null;
  status?: string;
  dwh?: "include" | "exclude";
  notes?: string;
}
interface Mapping {
  generated_at: string;
  source: string;
  entities: { deal: Field[]; person: Field[]; organization: Field[] };
}

/** Label -> CONSTANT_NAME (ASCII, snake→SCREAMING_SNAKE, Umlaute transliteriert). */
function constName(label: string): string {
  const map: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss" };
  const ascii = label
    .toLowerCase()
    .replace(/[äöüß]/g, (c) => map[c] ?? c)
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "");
  return ascii
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .toUpperCase();
}

function emitEntity(name: string, fields: Field[]): string {
  const seen = new Set<string>();
  const lines: string[] = [];
  lines.push(`export const ${name}_FIELDS = {`);
  for (const f of fields) {
    let c = constName(f.label);
    // Kollisionen (z. B. zwei "unbekannt") eindeutig machen.
    while (seen.has(c)) c = `${c}_${f.key.slice(0, 6).toUpperCase()}`;
    seen.add(c);
    const flags: string[] = [];
    if (f.status) flags.push(`status=${f.status}`);
    if (f.dwh) flags.push(`dwh=${f.dwh}`);
    const comment = flags.length ? `  // ${flags.join(", ")}` : "";
    lines.push(`  ${c}: ${JSON.stringify(f.key)},${comment}`);
  }
  lines.push(`} as const;`);
  return lines.join("\n");
}

function emitOptions(name: string, fields: Field[]): string {
  const withOpts = fields.filter((f) => f.options && f.options.length);
  if (!withOpts.length) return "";
  const lines: string[] = [`export const ${name}_OPTIONS = {`];
  const seen = new Set<string>();
  for (const f of withOpts) {
    let c = constName(f.label);
    while (seen.has(c)) c = `${c}_${f.key.slice(0, 6).toUpperCase()}`;
    seen.add(c);
    const entries = (f.options ?? [])
      .map((o) => `${o.id}: ${JSON.stringify(o.label)}`)
      .join(", ");
    lines.push(`  ${c}: { ${entries} } as Record<number, string>,`);
  }
  lines.push(`} as const;`);
  return lines.join("\n");
}

function emitExcluded(m: Mapping): string {
  const all = [...m.entities.deal, ...m.entities.person, ...m.entities.organization];
  const keys = all.filter((f) => f.dwh === "exclude").map((f) => f.key);
  return (
    `/** DSGVO/Irrelevanz: diese Keys dürfen NICHT nach core/marts. */\n` +
    `export const DWH_EXCLUDED_KEYS: ReadonlySet<string> = new Set(${JSON.stringify(keys, null, 2)});`
  );
}

function main(): void {
  const m = JSON.parse(readFileSync(IN, "utf8")) as Mapping;
  const header = [
    "/**",
    " * fields.generated.ts — AUTOMATISCH GENERIERT von scripts/generate-fields.ts.",
    " * NICHT von Hand editieren. Quelle: docs/field-mapping.json.",
    ` * Quelle-Stand: ${m.source} (${m.generated_at}).`,
    " *",
    " * Solange source='provisional-live-recon' ist, sind Labels teils abgeleitet.",
    " * Nach `npm run fetch:fields` (Fields API v2) hier neu generieren.",
    " */",
    "",
  ].join("\n");

  const blocks = [
    header,
    emitEntity("DEAL", m.entities.deal),
    emitOptions("DEAL", m.entities.deal),
    emitEntity("PERSON", m.entities.person),
    emitEntity("ORGANIZATION", m.entities.organization),
    emitOptions("ORGANIZATION", m.entities.organization),
    emitExcluded(m),
    "",
  ].filter(Boolean);

  writeFileSync(OUT, blocks.join("\n\n") + "\n");
  console.log(`Geschrieben: etl/pipedrive/fields.generated.ts (${m.entities.deal.length} Deal-Felder).`);
}

main();
