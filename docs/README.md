# `docs/` — Projektdokumentation

Narrative Doku, Entscheidungen und Referenzen. **Einstieg immer über `STATUS.md`.**

## Wichtigste zuerst

| Datei | Inhalt |
|---|---|
| `STATUS.md` | **Arbeitsstand & Handoff** — zu Beginn jeder Session lesen. Was ist gebaut/deployt, was offen, Branch- und Betriebsfakten. |
| `../CLAUDE.md` (Root) | **Verbindliche Domänen- & Repo-Regeln** (brutto, `null ≠ 0`, Kürzung ≠ Ausbuchung ≠ Haftungsquote, DSGVO, Join-Keys). Steht über allem. |
| `architecture.md` | Zielarchitektur (Quellen → ELT → Postgres raw/core/marts → Metabase). |
| `RUNBOOK.md` | Betrieb: Deploy, Verifikation, Wiederanlauf. |

## Referenz

| Datei | Inhalt |
|---|---|
| `field-mapping.md` / `.json` | Pipedrive-Custom-Fields (Hash-Key → Bedeutung, Status). `.json` ist die Maschinenform → generiert `etl/pipedrive/fields.generated.ts`. |
| `field-mapping-findings.md` | Narrative Herleitung/offene Fragen zum Feldmapping. |
| `labels.md` | Katalog der Pipedrive-`label_ids` (Gutachtenart, Fall-Alterung, Flags, Org-Typen). |

## Pläne & Strategien (je Phase)

| Datei | Inhalt |
|---|---|
| `plan-phase-1.md` … `plan-phase-5.md` | Plan je Phase (vor dem Bauen gegengelesen). |
| `status-phase-4.md` | Detailstand Phase 4 (autoiXpert/Gutachten). |
| `strategie-kuerzung-und-pdf.md` | Strategie Kürzungsschreiben-Zuordnung, Zahlungsverlauf & PDF-Parsing. |
| `adr/` | Architecture Decision Records (getroffene Grundsatzentscheidungen). |

## Prinzip

Doku beschreibt **Warum** und **Stand**; die **Regeln** stehen in `CLAUDE.md`, die
**Mechanik** in den READMEs der jeweiligen Ordner (`sql/`, `etl/`, `n8n/`, …).
