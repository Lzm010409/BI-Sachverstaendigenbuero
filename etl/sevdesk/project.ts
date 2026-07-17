/**
 * project.ts — DSGVO-Filter (Option A) für sevDesk-Objekte.
 *
 * Personenbezug wird NICHT persistiert. sevDesk-Rechnungen tragen den Rechnungs-
 * empfänger (oft eine natürliche Person = der Geschädigte) sowie Adress- und
 * Freitextfelder. Diese Projektion lässt ausschließlich die analysenotwendigen,
 * personenbezugsfreien Felder passieren — alles andere fällt vor dem Schreiben in
 * `raw` weg. Konsistent mit der Pipedrive-Freitextregel aus CLAUDE.md.
 *
 * Bewusst NICHT übernommen (Invoice): contact, contactPerson, createUser,
 *   sevClient, header, headText, footText, address*, addressCountry,
 *   customerInternalNote, einvoiceReference, additionalInformation, …
 * Bewusst NICHT übernommen (Position): der (voll eingebettete) invoice-Block bis
 *   auf dessen id, der Freitext `text` (Kennzeichen-/Namensrisiko),
 *   part.internalComment, part.image, additionalInformation, …
 */

type Json = Record<string, unknown>;

interface Ref {
  id: string | null;
  objectName: string | null;
}

function ref(o: unknown): Ref | null {
  if (o && typeof o === "object") {
    const r = o as Json;
    if (r.objectName != null || r.id != null) {
      return { id: r.id != null ? String(r.id) : null, objectName: r.objectName != null ? String(r.objectName) : null };
    }
  }
  return null;
}

/**
 * Whitelist-Projektion einer sevDesk-Invoice. Rückgabe geht 1:1 als
 * raw.sevdesk_invoices.payload in die DB.
 */
export function projectInvoice(inv: Json): Json {
  return {
    id: String(inv.id),
    objectName: inv.objectName ?? "Invoice",
    // invoiceNumber trägt das Aktenzeichen als Präfix (z. B. 0726/2012TG01) —
    // Geschäftsdatum/Fallnummer, KEIN Personenbezug. Bewusst behalten.
    invoiceNumber: inv.invoiceNumber ?? null,
    invoiceDate: inv.invoiceDate ?? null,
    deliveryDate: inv.deliveryDate ?? null,
    sendDate: inv.sendDate ?? null,
    status: inv.status ?? null,
    invoiceType: inv.invoiceType ?? null,
    sendType: inv.sendType ?? null,
    timeToPay: inv.timeToPay ?? null,
    currency: inv.currency ?? null,
    taxRate: inv.taxRate ?? null,
    taxText: inv.taxText ?? null,
    taxType: inv.taxType ?? null,
    taxRule: ref(inv.taxRule),
    smallSettlement: inv.smallSettlement ?? null,
    showNet: inv.showNet ?? null,
    discount: inv.discount ?? null,
    // Alle Beträge brutto/netto wie von sevDesk geliefert (keine Umrechnung).
    sumNet: inv.sumNet ?? null,
    sumTax: inv.sumTax ?? null,
    sumGross: inv.sumGross ?? null,
    sumDiscounts: inv.sumDiscounts ?? null,
    sumNetAccounting: inv.sumNetAccounting ?? null,
    sumTaxAccounting: inv.sumTaxAccounting ?? null,
    sumGrossAccounting: inv.sumGrossAccounting ?? null,
    paidAmount: inv.paidAmount ?? null,
    create: inv.create ?? null,
    update: inv.update ?? null,
  };
}

export interface ProjectedPosition {
  id: string;
  invoice_id: string;
  payload: Json;
}

/**
 * Whitelist-Projektion einer sevDesk-InvoicePos. `invoice` wird auf die reine
 * Objekt-ID reduziert; `text` (Freitext) wird verworfen. part/unity liefern die
 * Kategorie-Signale (nur id/name/partNumber/category), keinen Freitext.
 */
export function projectPosition(pos: Json): ProjectedPosition {
  const invoiceRef = ref(pos.invoice);
  const part = pos.part && typeof pos.part === "object" ? (pos.part as Json) : null;
  const unity = pos.unity && typeof pos.unity === "object" ? (pos.unity as Json) : null;
  const invoiceId = invoiceRef?.id ?? null;

  const payload: Json = {
    id: String(pos.id),
    objectName: pos.objectName ?? "InvoicePos",
    invoice_id: invoiceId,
    positionNumber: pos.positionNumber ?? null,
    quantity: pos.quantity ?? null,
    price: pos.price ?? null,
    // name = Positions-Label (Grundhonorar, Fahrtkosten, Lichtbilder …) = Kategorie.
    name: pos.name ?? null,
    taxRate: pos.taxRate ?? null,
    sumNet: pos.sumNet ?? null,
    sumTax: pos.sumTax ?? null,
    sumGross: pos.sumGross ?? null,
    sumDiscount: pos.sumDiscount ?? null,
    priceNet: pos.priceNet ?? null,
    priceGross: pos.priceGross ?? null,
    priceTax: pos.priceTax ?? null,
    unity: unity
      ? { id: unity.id != null ? String(unity.id) : null, name: unity.name ?? null, translationCode: unity.translationCode ?? null }
      : ref(pos.unity),
    part: part
      ? {
          id: part.id != null ? String(part.id) : null,
          name: part.name ?? null,
          partNumber: part.partNumber ?? null,
          category: ref(part.category),
        }
      : ref(pos.part),
  };

  return { id: String(pos.id), invoice_id: invoiceId ?? "", payload };
}

/**
 * Whitelist-Projektion eines sevDesk-Vouchers (Beleg). Für Phase 5 relevant sind
 * die „Forderungsverlust [Aktenzeichen]"-Belege (die tatsächliche Ausbuchung).
 *
 * DSGVO: `supplier`/`supplierName` (Kreditor — kann natürliche Person sein) und
 * jegliche Adress-/Kontaktfelder werden VERWORFEN. `description` trägt nur den
 * Belegtitel inkl. Aktenzeichen (Geschäftsschlüssel, kein Personenbezug) und bleibt.
 * Alle Beträge brutto/netto wie geliefert (keine Umrechnung).
 */
export function projectVoucher(v: Json): Json {
  return {
    id: String(v.id),
    objectName: v.objectName ?? "Voucher",
    // Belegtitel = „Forderungsverlust <Aktenzeichen>" (Geschäftsschlüssel).
    description: v.description ?? null,
    voucherDate: v.voucherDate ?? null,
    status: v.status ?? null,
    creditDebit: v.creditDebit ?? null,
    voucherType: v.voucherType ?? null,
    taxRule: ref(v.taxRule),
    taxType: v.taxType ?? null,
    currency: v.currency ?? null,
    sumNet: v.sumNet ?? null,
    sumTax: v.sumTax ?? null,
    sumGross: v.sumGross ?? null,
    sumNetAccounting: v.sumNetAccounting ?? null,
    sumTaxAccounting: v.sumTaxAccounting ?? null,
    sumGrossAccounting: v.sumGrossAccounting ?? null,
    paidAmount: v.paidAmount ?? null,
    create: v.create ?? null,
    update: v.update ?? null,
  };
}
