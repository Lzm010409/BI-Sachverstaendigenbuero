# ADR 0002 — Feldmetadaten über Pipedrive Fields API v2

**Status:** akzeptiert
**Datum:** 2026-07

## Kontext

Pipedrive liefert Custom-Field-Werte nur als Hash-Keys ohne Labels. Für ein
autoritatives Feldmapping (Phase 0, Aufgabe 3) brauchen wir die
Feldmetadaten-Endpunkte (Key → Label, Typ, Optionsliste). Der Build-Auftrag
verlangt ausdrücklich, die aktuelle API-Version zu prüfen, nicht aus dem
Gedächtnis zu arbeiten.

## Recherche (2026-07, aktuelle Doku)

Pipedrive hat eine **Fields API v2** eingeführt, die Feldmetadaten liefert:

- `GET /api/v2/dealFields`
- `GET /api/v2/personFields`
- `GET /api/v2/organizationFields`

- **Pagination:** cursor-basiert (`limit` bis 500, `cursor` als opaker String) —
  anders als v1, das offset-basiert (`start`) arbeitet.
- **Auth:** `api_token`-Query-Parameter (read-only Token genügt) oder OAuth
  Bearer.
- v1 (`/api/v1/dealFields`, offset-Pagination) existiert weiter, ist aber die
  ältere Variante.

Quellen:
- https://pipedrive.readme.io/docs/pipedrive-api-v2-migration-guide
- https://developers.pipedrive.com/changelog/post/introducing-new-fields-api-v2

## Entscheidung

`scripts/fetch-field-mapping.ts` nutzt die **v2**-Endpunkte mit
Cursor-Pagination für alle drei Entitätstypen (Deal, Person, Organisation).

## Konsequenzen

- Ein read-only Token reicht (🧑 MENSCH stellt ihn bereit).
- Der Extraktor der Deal-Daten (Phase 2) nutzt weiterhin die im MCP/SDK
  verfügbaren Deal-Endpunkte; die Feld*metadaten* kommen ausschließlich aus v2.
- Sollte Pipedrive die v2-Fields-Endpunkte ändern, ist nur dieses eine Skript
  betroffen; das committete `docs/field-mapping.json` bleibt reproduzierbar.
