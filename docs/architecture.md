# Architektur

## Datenfluss

```
Pipedrive ─┐
sevDesk   ─┤   ELT (TypeScript, Cron-Container auf Coolify)
autoiXpert─┤        │  Extraktoren schreiben Rohantworten unverändert
Legacy-PDF─┘        ▼
                PostgreSQL
                ├─ raw    JSONB, unverändert, heilig, reproduzierbar
                ├─ core   fact_* / dim_*, normalisiert, DSGVO-gefiltert
                └─ marts  v_* Views für Metabase
                        │
                        ▼
                  Metabase OSS  (eigene App-DB, getrennt vom Warehouse)

n8n:  Mail-Eingang → Anhang/Aktenzeichen → Abrechnungs-Pipeline (Phase 5)
```

## Schema-Verantwortung & Rollen

| Schema | Inhalt | Wer schreibt | Wer liest |
|---|---|---|---|
| `raw` | Rohantworten (JSONB) | Rolle `etl` | `etl` |
| `core` | Fakten/Dimensionen | Rolle `etl` | `etl`, `metabase_ro` |
| `marts` | Views | Migrationen (`etl`) | `metabase_ro` |

- Rolle `etl`: schreibt `raw`, liest/schreibt `core`.
- Rolle `metabase_ro`: liest nur `marts` und `core`. **Kein** Zugriff auf `raw`
  (dort liegen die DSGVO-sensiblen Freitexte/Kennzeichen).

## Prinzipien

- **Rohdaten sind heilig.** `raw` wird nie transformiert oder gelöscht. Fällt
  später ein Feld auf, wird aus `raw` neu abgeleitet — nicht nachgeladen.
- **Transformation als SQL** (nummerierte Migrationen + Views), kein dbt bis
  >20 Modelle (ADR 0001).
- **DSGVO an der `raw`→`core`-Grenze durchgesetzt:** `DWH_EXCLUDED_KEYS` aus
  `fields.generated.ts` sowie alle Freitext-/Kennzeichen-Felder bleiben in `raw`.
- **Aktenzeichen** ist der systemübergreifende Join-Key (siehe `CLAUDE.md`).

## Extraktions-Prinzipien (ab Phase 2)

- Inkrementell über `updated_since`, Wasserstand in `raw._sync_state`.
- Cursor-Pagination vollständig durchlaufen.
- Rate Limits + exponentielles Backoff, wiederaufnehmbar.
- Alle Zeitstempel `timestamptz` in UTC; `local_*_date` nicht mit UTC verwechseln.
- Auch verlorene/archivierte Deals holen (Leitfrage 4).
