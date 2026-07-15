# Label-Katalog (Pipedrive)

> Aus Live-Sampling abgeleitet (100 Deals + Org-Sample über MCP,
> `include_labels=true`). **Kein** Zugriff auf das Label-Management-Endpoint —
> selten genutzte Labels können fehlen. Zählwerte sind Stichproben-Häufigkeit.

## Deal-Labels — drei Bedeutungsgruppen in einem Feld

Der ETL muss `deal.label_ids` in drei Gruppen zerlegen:

### a) Gutachtenart (Auswertungsdimension, Leitfrage 1/6/10)

| ID | Name | Häufigkeit (100er-Scan) |
|---|---|---|
| 28 | Haftpflichgutachten *(sic, so in Pipedrive)* | 98 |
| 36 | BEWERTUNG (Wertermittlung) | 2 |

**Wichtig:** In Pipedrive gibt es faktisch nur diese grobe Unterscheidung
(Haftpflicht vs. Bewertung). Die **feingliedrige Gutachtenart** (Kasko,
Kurzgutachten, Reparaturbestätigung, Beweissicherung, Leasingrückläufer …) ist
in Pipedrive-Labels **nicht** abgebildet → muss aus **autoiXpert** (Phase 4)
kommen. Das ist eine offene MENSCH-Frage (siehe field-mapping-findings.md).

### b) Fall-Alterung (auto-gesetzt, NICHT Gutachtenart)

| ID | Name |
|---|---|
| 61 | Neuer Fall |
| 62 | Mittelalter Fall |
| 63 | Überfälliger Fall |

Vermutlich per Automatik/n8n gesetzt (fast jeder Deal trägt 61). Für Kennzahlen
ignorieren bzw. als eigene Betriebs-Dimension behandeln, nicht als Gutachtenart.

### c) Fall-Flags

| ID | Name | Relevanz |
|---|---|---|
| 60 | OHNE RECHTSANWALT | Fälle ohne Anwalt — relevant für Leitfrage 2/3 (Durchsetzung ggf. schwächer). |

## Org-Labels — Entitätstyp

| ID | Bedeutung | Beispiele |
|---|---|---|
| 35 | Versicherer | HUK Coburg, Ergo, Provinzial, Cosmos Direkt, Verti |
| 32 | Auftraggeber / Anwalt / Privat | Kanzleien, Privatpersonen, „EIGEN" |

`deal.org_id` referenziert — wenn gesetzt — den Versicherer (Org mit Label 35).
Befüllungsgrad im 100er-Scan: **51/100**. Prozess wird laut Inhaber verbessert.
