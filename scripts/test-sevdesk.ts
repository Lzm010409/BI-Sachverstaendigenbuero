/**
 * test-sevdesk.ts — verifiziert Phase 3 (sevDesk positionsscharf).
 *
 * Teil A (ohne DB): DSGVO-Filter — projectInvoice()/projectPosition() dürfen
 *   KEINEN Personenbezug durchlassen (contact, Adresse, Freitext text, …).
 * Teil B (DB, read-only): assertet core.fact_rechnungsposition + Konsistenz gegen
 *   die bekannte Beispiel-Rechnung 129183018 (Aktenzeichen 0726/2012TG).
 *
 * Teil B setzt voraus, dass die Rechnung in raw liegt: lokal vorher
 *   `ALLOW_LOAD_GOLDEN=1 npm run load:sevdesk`, in Produktion nach der Extraktion.
 * Read-only: verändert nichts, kann daher gegen die Produktions-Warehouse laufen.
 */
import { makePool } from "../etl/db.js";
import { projectInvoice, projectPosition } from "../etl/sevdesk/project.js";

const INVOICE_ID = 129183018;

// name -> erwartete Kategorie (kontrollierter Katalog).
const ERWARTETE_KATEGORIE: Record<string, string> = {
  "SV-Honorar": "Grundhonorar",
  "Lichtbilder": "Fotokosten",
  "Fahrtkosten": "Fahrtkosten",
  "Porto &amp; Telefon (pauschal)": "Porto/Telefon",
  "Bewertungsabfrage": "Bewertungsabfrage",
  "EDV Kosten": "EDV-Kosten",
  "Schichtdickenmessung": "Schichtdickenmessung",
  "Restwertermittlung": "Restwertermittlung",
};

let failed = 0;
function check(ok: boolean, msg: string): void {
  if (!ok) { console.error(`✗ ${msg}`); failed++; }
}

/** Teil A: rekursiv prüfen, dass verbotene Schlüssel/Werte nicht persistiert werden. */
function assertNoPii(): void {
  const roh = {
    id: 999, objectName: "Invoice", invoiceNumber: "0726/2012TG01",
    contact: { id: "135060698", objectName: "Contact" },
    contactPerson: { id: "851050", objectName: "SevUser" },
    createUser: { id: "851050", objectName: "SevUser" },
    header: "Rechnung an Max Mustermann",
    headText: "Sehr geehrter Herr Mustermann",
    footText: "IBAN DE12 3456 …",
    addressName: "Max Mustermann", addressStreet: "Musterstr. 1",
    addressZip: "12345", addressCity: "Musterstadt",
    sumGross: "1480.19", taxRule: { id: "1", objectName: "TaxRule" },
  };
  const inv = projectInvoice(roh);
  const invKeys = Object.keys(inv);
  const verbotenInv = ["contact", "contactPerson", "createUser", "header", "headText",
    "footText", "addressName", "addressStreet", "addressZip", "addressCity"];
  for (const k of verbotenInv) {
    check(!invKeys.includes(k), `Invoice-Projektion enthält verbotenes Feld '${k}'`);
  }
  const invBlob = JSON.stringify(inv);
  check(!invBlob.includes("Mustermann"), "Invoice-Projektion enthält Klarnamen");
  check(!invBlob.includes("135060698"), "Invoice-Projektion enthält Contact-ID");
  check(inv.invoiceNumber === "0726/2012TG01", "Invoice-Projektion verliert invoiceNumber");
  check((inv.sumGross as string) === "1480.19", "Invoice-Projektion verliert sumGross");

  const rohPos = {
    id: 345467434, objectName: "InvoicePos", name: "SV-Honorar",
    invoice: { id: "129183018", objectName: "Invoice", header: "Rechnung an Max Mustermann", addressName: "Max Mustermann" },
    text: "Gutachten KFZ B-XX 1234, Halter Max Mustermann",
    quantity: 1, price: 1109.85, sumGross: 1320.72, taxRate: 19,
    unity: { id: "7", objectName: "Unity", name: "pauschal", translationCode: "UNITY_BLANKET" },
    part: { id: "25069008", objectName: "Part", name: "SV-Honorar", partNumber: "1002",
            internalComment: "interner Vermerk", category: { id: "617272", objectName: "Category" } },
  };
  const { payload: pos } = projectPosition(rohPos);
  const posKeys = Object.keys(pos);
  check(!posKeys.includes("text"), "Positions-Projektion enthält Freitext 'text'");
  check(pos.invoice_id === "129183018", "Positions-Projektion verliert invoice_id");
  const posBlob = JSON.stringify(pos);
  check(!posBlob.includes("Mustermann"), "Positions-Projektion enthält Klarnamen (text/invoice)");
  check(!posBlob.includes("B-XX 1234"), "Positions-Projektion enthält Kennzeichen");
  check(!posBlob.includes("interner Vermerk"), "Positions-Projektion enthält part.internalComment");
  check(!posBlob.includes("header"), "Positions-Projektion enthält eingebettete Invoice-Felder");
  check((pos.part as Record<string, unknown>)?.partNumber === "1002", "Positions-Projektion verliert part.partNumber");
}

async function assertDb(): Promise<void> {
  const pool = makePool();
  try {
    const rows = await pool.query<{
      position_name: string; kategorie: string; aktenzeichen: string | null; summe_brutto: string;
    }>(
      "SELECT position_name, kategorie, aktenzeichen, summe_brutto FROM core.fact_rechnungsposition WHERE invoice_id = $1 ORDER BY position_nr",
      [INVOICE_ID],
    );

    if (rows.rowCount === 0) {
      console.error(`⚠ Rechnung ${INVOICE_ID} nicht in raw — Teil B übersprungen. ` +
        `Lokal: 'ALLOW_LOAD_GOLDEN=1 npm run load:sevdesk' ausführen.`);
      return;
    }

    check(rows.rowCount === 8, `Positionsanzahl: ist ${rows.rowCount}, erwartet 8`);

    for (const r of rows.rows) {
      const erwartet = ERWARTETE_KATEGORIE[r.position_name];
      check(erwartet !== undefined && r.kategorie === erwartet,
        `Kategorie '${r.position_name}': ist '${r.kategorie}', erwartet '${erwartet ?? "?"}'`);
      check(r.aktenzeichen === "0726/2012TG",
        `Aktenzeichen für '${r.position_name}': ist '${r.aktenzeichen}', erwartet '0726/2012TG'`);
    }

    const summe = rows.rows.reduce((a, r) => a + Number(r.summe_brutto), 0);
    check(Math.abs(summe - 1480.19) < 0.005, `Σ Positionen brutto: ist ${summe.toFixed(2)}, erwartet 1480.19`);

    const kons = await pool.query<{ differenz: string; positionen_brutto: string; rechnung_brutto: string }>(
      "SELECT differenz, positionen_brutto, rechnung_brutto FROM marts.v_rechnung_konsistenz WHERE invoice_id = $1",
      [INVOICE_ID],
    );
    check(kons.rowCount === 1 && Math.abs(Number(kons.rows[0]?.differenz)) < 0.005,
      `Konsistenz: Positionen(${kons.rows[0]?.positionen_brutto}) == Rechnung(${kons.rows[0]?.rechnung_brutto}), differenz=${kons.rows[0]?.differenz}`);
  } finally {
    await pool.end();
  }
}

async function main(): Promise<void> {
  assertNoPii();
  await assertDb();
  if (failed === 0) {
    console.log("✓ sevDesk-Test grün: DSGVO-Filter + Positionsstruktur + Konsistenz stimmen.");
  } else {
    console.error(`\n✗ sevDesk-Test: ${failed} Prüfung(en) fehlgeschlagen.`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
