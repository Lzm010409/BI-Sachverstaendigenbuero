# `etl/sevdesk/` — sevDesk-Extraktoren (Rechnungen, Positionen, Geld)

sevDesk ist die **Finanzquelle**: Rechnungen, Positionen (positionsscharfer Umsatz),
Belege und der **Zahlungsverlauf** (Kürzung/Durchsetzung).

## Dateien

| Datei | Was | Ziel |
|---|---|---|
| `client.ts` | REST v1-Client. Auth = Token **direkt** im `Authorization`-Header (ohne „Bearer"), offset/limit-Pagination, Backoff. `https://my.sevdesk.de/api/v1`. | — |
| `extract-invoices.ts` | Rechnungen (Kopf, Summen brutto/netto) | `raw.sevdesk_invoices` |
| `extract-positions.ts` | je Rechnung `getPositions` (embed part/unity) | `raw.sevdesk_invoice_positions` |
| `extract-vouchers.ts` | „Forderungsverlust <Aktenzeichen>"-Belege = tatsächliche **Ausbuchung** | `raw.sevdesk_vouchers` |
| `extract-payments.ts` | je Rechnung `getCheckAccountTransactionLogs` = **Buchungen** (Zahlung vs. Ausbuchung) | `raw.sevdesk_invoice_bookings` |
| `project.ts` | DSGVO-Whitelist für alle vier (verwirft Empfänger/Kontakt/IBAN/Freitext) | — |
| `load-kategorien.ts` | lädt den Positionskategorie-Seed (`fixtures/positionskategorie.json`) → `core.dim_positionskategorie_regel` | — |

## Das Geld-Modell (Kernstück Phase 5)

sevDesk bucht bei Fallabschluss die Rechnung **voll** (Zahlung + Ausbuchung) → der
offene Betrag ist ~0. Die echte Kürzung ist deshalb **nicht** aus `paidAmount`
ablesbar, sondern aus den **einzelnen Buchungen** je Rechnung
(`extract-payments.ts`), die nach Konto unterscheiden:

- **„Geschäftskonto Postbank"** (Konto 1100, `online`) = tatsächlicher Zahlungseingang
- **„Ausgebuchte Rechnungen"** (Konto 1203, `offline`) = Ausbuchung (Verlust)

Daraus rechnen die Views (`sql/032`):
`Kürzung = Rechnung − erste Zahlung` · `Ausbuchung = Σ Ausbuchungsbuchungen` ·
`Durchsetzung = 1 − Ausbuchung/Kürzung` (nur `won`; USt-Einbehalt und Haftungsquote
raus). Der **Grund** kommt aus dem Pipedrive-Ausbuchungsgrund bzw. (Detail) aus den
Kürzungsschreiben (n8n, `fact_kuerzungsereignis.kuerzungsgrund`).

## DSGVO

`project.ts` lässt nur Fakten/Zahlen/Konto durch. **Nicht** persistiert: Rechnungs-
empfänger/Kontakt (oft der Geschädigte), IBAN, `paymtPurpose`/Verwendungszweck,
Freitext. Aktenzeichen (aus Rechnungsnummer/Belegtitel) ist Geschäftsdatum → bleibt.

## Betrieb

Egress zu sevDesk ist nur aus dem Coolify-Container offen (aus Web-Sessions
geblockt). Fremd-API-Änderungen daher **gegen die aktuelle sevDesk-Doku** prüfen,
nie aus dem Gedächtnis.
