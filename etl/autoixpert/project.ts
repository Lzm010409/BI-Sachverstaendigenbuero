/**
 * project.ts — DSGVO-Filter (Option A) für autoiXpert-Reports.
 *
 * autoiXpert ist personenbezugs-SCHWER. Diese Projektion ist DENY-BY-DEFAULT: das
 * Ausgabe-Objekt wird ausschließlich aus explizit benannten, personenbezugsfreien
 * Feldern zusammengesetzt. Unbekannte/nicht gelistete Keys passieren NIE. Nichts
 * wird durchgereicht, was nicht hier steht.
 *
 * BEWUSST VERWORFEN (nach CLAUDE.md verboten bzw. Personenbezug):
 *   - claimant, owner_of_claimants_car, author_of_damage,
 *     owner_of_author_of_damages_car — natürliche Personen (Klarname, Anschrift,
 *     E-Mail, Telefon, **license_plate**, insurance_number).
 *   - car.vin, car.license_plate — nach CLAUDE.md verboten.
 *   - car.damage_description / repaired_previous_damage / unrepaired_previous_damage
 *     / *_condition / condition_comment / roadworthiness — Freitext.
 *   - accident.location / circumstances / plausibility / police_* — Freitext/Ort.
 *   - visits, photos, documents, paint_thickness_measurements, axles/tires,
 *     labels, custom_fields — nicht benötigt bzw. Freitext/URLs/Session-IDs.
 *   - insurance/lawyer/garage: contract_number, case_number, Anschrift, E-Mail,
 *     Telefon — Personenbezug. NUR organization_name (juristische Person, nach
 *     CLAUDE.md im Klartext erlaubt) + contact_id (pseudonyme autoiXpert-ID).
 *
 * BEWUSST BEHALTEN (personenbezugsfrei, analysenotwendig):
 *   - Identität/Workflow: id, external_id, token(=Aktenzeichen), type, state, Daten.
 *   - Versicherer/Anwalt/Werkstatt/Vermittler als organization_name — juristische
 *     Personen. `insurance.organization_name` schließt die zentrale Lücke für
 *     Leitfrage 2 (Versicherer je Fall), die in Pipedrive nur dünn befüllt ist.
 *   - Fahrzeug-Klassenmerkmale ohne Bezug (make/model/shape/Leistung/Erstzulassung/
 *     Laufleistung) — KEIN VIN, KEIN Kennzeichen.
 *   - Fachwerte (WBW/Restwert/Wertminderung/Reparaturkosten/Nutzungsausfall) —
 *     s. u.: im aufgenommenen (state=recorded) Sample NOCH NICHT enthalten.
 */

type Json = Record<string, unknown>;

function str(v: unknown): string | null {
  return v == null ? null : String(v);
}

function num(v: unknown): number | null {
  if (v == null || v === "") return null;
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

/** Juristische Person auf { organization_name, contact_id } reduzieren. */
function org(o: unknown): Json | null {
  if (!o || typeof o !== "object") return null;
  const r = o as Json;
  const name = str(r.organization_name);
  const cid = str(r.contact_id);
  if (name == null && cid == null) return null;
  return { organization_name: name, contact_id: cid };
}

/**
 * Vermittler/Auftragsquelle → NUR pseudonyme contact_id, KEIN Klartext-Name.
 * Grund: der Vermittler ist NICHT von der CLAUDE.md-Klartext-Erlaubnis für
 * juristische Personen (Versicherer/Werkstatt/Anwalt) gedeckt und kann eine
 * natürliche Person sein (in einem echten Sample trug organization_name einen
 * Personennamen statt einer Firma).
 * Die contact_id ist ein stabiler Pseudonym-Schlüssel → Gruppierung je Quelle für
 * Leitfrage 4 bleibt möglich, ohne Personenbezug. (Ob Vermittler-Namen für LF4
 * doch gebraucht werden, ist eine offene Frage an den Inhaber — s. plan-phase-4 §7.)
 */
function intermediaryRef(o: unknown): Json | null {
  if (!o || typeof o !== "object") return null;
  const cid = str((o as Json).contact_id);
  return cid == null ? null : { contact_id: cid };
}

// Kalkulations-Dokumente, deren bloße EXISTENZ ein Fachsignal ist (Bewertung/
// Restwert/Minderwert/Reparatur erstellt) — auch wenn die Zahl nur im PDF steht.
const DOK_SIGNALE: Record<string, string> = {
  dat_damage_calculation: "hat_dat_kalkulation",       // Reparaturkosten
  dat_market_analysis: "hat_dat_marktanalyse",         // WBW/Marktwert
  diminished_value_protocol: "hat_minderwertprotokoll", // Wertminderung
  custom_residual_value_bid_list: "hat_restwertgebote", // Restwert
};

/**
 * Dokument-PRÄSENZ als DSGVO-sicheres Signal. NUR die `type`-Werte werden gelesen
 * (keine download_url, keine title — Titel können Dateinamen/Datum enthalten). Gibt
 * die Menge vorhandener Typen + Bool-Flags für die kalkulationsrelevanten zurück.
 */
function dokumente(report: Json): Json {
  const docs = Array.isArray(report.documents) ? (report.documents as Json[]) : [];
  const typen = new Set<string>();
  for (const d of docs) {
    const t = str(d?.type);
    if (t) typen.add(t);
  }
  const flags: Json = {};
  for (const [t, flag] of Object.entries(DOK_SIGNALE)) flags[flag] = typen.has(t);
  return { typen: [...typen].sort(), ...flags };
}

/**
 * Fachwerte. BESTÄTIGT vom Inhaber (2026-07-15) an einem FERTIGEN Gutachten
 * (state=done, completion_date gesetzt): WBW, Restwert, Wertminderung und
 * Reparaturkosten stehen NICHT als strukturierte Felder in der externalApi —
 * sie existieren ausschließlich in den generierten PDFs (dat_market_analysis,
 * custom_residual_value_bid_list, diminished_value_protocol, dat_damage_calculation).
 * Diese Projektion liefert die Zahlen daher bewusst als null; ob/woher sie kommen,
 * ist eine offene Architekturfrage (PDF-Parsing vs. Pipedrive-Reparaturkosten vs.
 * evtl. separater Valuation-Endpunkt — s. plan-phase-4 §7). `_quelle_pdf_only`
 * dokumentiert den Befund direkt am Datum. Die EXISTENZ der Kalkulationen wird über
 * dokumente() als Signal geführt.
 */
function fachwerte(): Json {
  return {
    wiederbeschaffungswert: null,
    restwert: null,
    wertminderung: null,
    reparaturkosten_netto: null,
    reparaturkosten_brutto: null,
    nutzungsausfall_tagessatz: null,
    _quelle_pdf_only: true,
  };
}

/**
 * Whitelist-Projektion eines autoiXpert-Reports. Rückgabe geht 1:1 als
 * raw.autoixpert_gutachten.payload in die DB (bereits DSGVO-gefiltert).
 */
export function projectGutachten(report: Json): Json {
  const car = (report.car ?? {}) as Json;
  const accident = (report.accident ?? {}) as Json;
  return {
    id: str(report.id),
    external_id: str(report.external_id),
    // token ist bei autoiXpert das Aktenzeichen (MMJJ/NummerTG) — Join/Kreuzcheck.
    token: str(report.token),
    type: str(report.type), // liability -> Haftpflicht, valuation -> Bewertung
    state: str(report.state),
    created_at: str(report.created_at),
    updated_at: str(report.updated_at),
    order_date: str(report.order_date),
    completion_date: str(report.completion_date),
    ordering_method: str(report.ordering_method),
    order_placed_by_claimant: report.order_placed_by_claimant ?? null,
    use_factoring: report.use_factoring ?? null,
    use_dekra_fees: report.use_dekra_fees ?? null,
    vin_was_checked: report.vin_was_checked ?? null,
    responsible_assessor_id: str(report.responsible_assessor_id),
    location_id: str(report.location_id),
    // Juristische Personen (Klartext erlaubt). insurance -> Leitfrage 2.
    insurance: org(report.insurance),
    lawyer: org(report.lawyer),
    garage: org(report.garage),
    // Vermittler NUR pseudonym (kann natürliche Person sein) — s. intermediaryRef().
    intermediary: intermediaryRef(report.intermediary),
    // Fahrzeug-Klassenmerkmale ohne Personenbezug (KEIN VIN, KEIN Kennzeichen).
    car: {
      make: str(car.make),
      model: str(car.model),
      shape: str(car.shape),
      performance_kw: num(car.performance_kw),
      first_registration_date: str(car.first_registration_date),
      latest_registration_date: str(car.latest_registration_date),
      next_general_inspection_date: str(car.next_general_inspection_date),
      mileage_meter: num(car.mileage_meter),
      mileage_as_stated: num(car.mileage_as_stated),
    },
    accident: {
      date: str(accident.date), // Schadendatum; Ort/Freitext bewusst verworfen
    },
    // Welche Kalkulationen existieren (Bewertung/Restwert/Minderwert/Reparatur)?
    dokumente: dokumente(report),
    fachwerte: fachwerte(),
  };
}
