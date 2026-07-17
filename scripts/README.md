# `scripts/` — Hilfsskripte (Migration, Feldmapping, Tests, Betrieb)

Einmalige bzw. Betriebs-Skripte rund um die ETL. Alle als npm-Scripts in
`package.json` aufrufbar.

## Kern

| Skript | npm | Was |
|---|---|---|
| `migrate.ts` | `npm run migrate` | Führt `sql/*.sql` in Reihenfolge aus, checksum-gesichert (`_meta._migrations`). Läuft beim Deploy zuerst. Bricht ab, wenn eine **bereits angewandte** Migration geändert wurde → Korrekturen als neue Datei. |
| `fetch-field-mapping.ts` | `npm run fetch:fields` | Holt die Pipedrive **Fields API v2** → `docs/field-mapping.json` (autoritatives Feldmapping). |
| `generate-fields.ts` | `npm run generate:fields` | Erzeugt `etl/pipedrive/fields.generated.ts` (benannte Konstanten) aus `field-mapping.json`. Die generierte Datei **nie von Hand editieren**. |

## Lokale Verifikation (ohne Prod)

Gegen ein Wegwerf-Postgres 16, mit dem Golden Dataset / sevDesk-Sample aus `fixtures/`:

| Skript | npm | Was |
|---|---|---|
| `load-golden.ts` | `npm run load:golden` | lädt `fixtures/golden-deals.json` nach `raw` (braucht `ALLOW_LOAD_GOLDEN=1`). |
| `test-golden.ts` | `npm run test:golden` | prüft `core`/`marts` gegen die handgeprüften Erwartungswerte. |
| `load-sevdesk.ts` / `test-sevdesk.ts` | `npm run load:sevdesk` / `test:sevdesk` | dito für die sevDesk-Positionslogik. |

Ablauf: `migrate` → `load:*` → `test:*`. So lässt sich die Transformationslogik
prüfen, ohne die Produktivsysteme anzufassen.

## Betrieb

- `backup.sh` — DB-Backup (Coolify-`backup`-Service, Profil manuell).
- `db/` — DB-Hilfsskripte (Rollen/Grants etc.).

Secrets kommen **immer aus der Umgebung** (`.env`, gitignored) — nie ins Repo,
nie in Logs.
