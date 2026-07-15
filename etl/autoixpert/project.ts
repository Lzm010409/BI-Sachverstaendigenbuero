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
 * Fachwerte aus dem Report ziehen. ACHTUNG: Im gelieferten Sample (state=recorded,
 * completion_date=null) sind WBW/Restwert/Wertminderung/Reparaturkosten NICHT
 * enthalten — sie entstehen erst im fertigen Gutachten (bzw. in der
 * DAT-Schadenskalkulation, die als separates Dokument geführt wird). Die konkreten
 * Feldnamen/Verschachtelung sind daher NOCH UNBESTÄTIGT und müssen gegen ein
 * FERTIGES Gutachten (completion_date gesetzt) verifiziert werden, bevor diese
 * Projektion produktiv Fachwerte liefert. Bis dahin: defensive Lese-Versuche über
 * plausible Kandidaten-Pfade, numerisch gecoerct (nicht-numerisches -> null), damit
 * kein Freitext/Personenbezug versehentlich durchrutscht. Alle Treffer sind bis zur
 * Verifikation als „best effort" zu behandeln.
 */
function fachwerte(report: Json): Json {
  const valuation = (report.valuation ?? {}) as Json;
  const calc = (report.damage_calculation ?? report.damageCalculation ?? {}) as Json;
  return {
    // TODO(Phase 4): Feldnamen gegen ein FERTIGES Gutachten bestätigen.
    wiederbeschaffungswert:
      num(report.replacement_value) ?? num(valuation.replacement_value) ?? num(valuation.market_value),
    restwert:
      num(report.residual_value) ?? num(valuation.residual_value),
    wertminderung:
      num(report.decrease_in_value) ?? num(valuation.decrease_in_value),
    reparaturkosten_netto:
      num(calc.repair_costs_net) ?? num(report.repair_costs_net),
    reparaturkosten_brutto:
      num(calc.repair_costs_gross) ?? num(report.repair_costs_gross),
    nutzungsausfall_tagessatz:
      num(report.loss_of_use_per_day) ?? num(valuation.loss_of_use_per_day),
    // Herkunft der Werte transparent halten, solange unbestätigt:
    _fachwerte_verifiziert: false,
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
    intermediary: org(report.intermediary),
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
    fachwerte: fachwerte(report),
  };
}
