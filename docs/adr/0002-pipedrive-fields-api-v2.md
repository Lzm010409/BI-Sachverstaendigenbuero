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

## Nachtrag: Zugang läuft über den Pipedrive-OAuth-MCP

Der Inhaber stellt Pipedrive **nicht** über einen persönlichen REST-Token bereit,
sondern über den **OAuth-MCP-Server**. Konsequenz:

- Der MCP stellt **kein** Feldmetadaten-Endpoint bereit (nur `getDeals`,
  `getOrganizations` etc.). Damit lassen sich Feld-*labels* nur aus Werten
  ableiten/verifizieren, nicht autoritativ auslesen.
- `docs/field-mapping.json` bleibt daher vorerst „provisional-live-recon"
  (Status je Feld). Die offenen Labels werden per Live-Sampling eingegrenzt und
  vom Inhaber bestätigt (siehe `field-mapping-findings.md`).
- `fetch-field-mapping.ts` bleibt im Repo und ist lauffähig, **falls** je ein
  OAuth-Bearer-/REST-Token bereitsteht, der `/api/v2/dealFields` erreichen darf.

## Konsequenzen

- Der Extraktor der Deal-Daten (Phase 2) nutzt die MCP-/REST-Deal-Endpunkte.
- Sollte Pipedrive die v2-Fields-Endpunkte ändern, ist nur dieses eine Skript
  betroffen; das committete `docs/field-mapping.json` bleibt reproduzierbar.
