# RUNBOOK

Betriebshandbuch. Wächst mit den Phasen. Stand: Phase 1 (Infrastruktur).

## Architektur in einem Satz

Eine bestehende PostgreSQL-Instanz (Coolify) hält Metabases App-DB **und** die
Warehouse-DB `warehouse` (Schemas `raw`/`core`/`marts`). Eine ETL-Ressource
(`docker-compose.yml`) übernimmt Migrationen und Backup. Metabase liest das
Warehouse als Datenquelle mit dem read-only User `metabase_ro`.

---

## Erst-Einrichtung (einmalig)

1. **Rollen + DB anlegen** — mit Admin/Superuser der bestehenden Instanz:
   ```
   psql "postgresql://<admin>:<pw>@<host>:5432/postgres" \
     -f scripts/db/00-bootstrap-roles.sql
   ```
   Vorher die `<…_PASSWORD>`-Platzhalter durch echte Werte ersetzen.

2. **Coolify-Ressource** aus diesem Repo (`docker-compose.yml`) anlegen und an
   **dasselbe Netzwerk** wie die Postgres-Instanz hängen (Coolify: gemeinsames/
   predefined network), damit `WAREHOUSE_DB_HOST` auflösbar ist.

3. **Secrets** an der Ressource setzen (Environment, als secret):
   `WAREHOUSE_DB_HOST`, `WAREHOUSE_DB_PORT`, `WAREHOUSE_DB_NAME`,
   `ETL_DB_USER`, `ETL_DB_PASSWORD`, `PG_MAJOR`.

4. **Deploy.** Der `migrate`-Service läuft an, wendet `sql/001_init.sql` an und
   beendet sich mit 0. Bei Fehler schlägt der Deploy fehl (gewollt).

5. **Metabase-Datenquelle** hinzufügen: Metabase → Admin → Datenbanken →
   PostgreSQL. Host/Port der Instanz, DB `warehouse`, User `metabase_ro`,
   Passwort `METABASE_RO_PASSWORD`.

6. **Negativtest DSGVO:** als `metabase_ro` prüfen, dass `raw` **nicht** lesbar
   ist:
   ```
   psql "postgresql://metabase_ro:<pw>@<host>:5432/warehouse" \
     -c "SELECT * FROM raw._sync_state LIMIT 1;"   -- muss: permission denied
   ```

---

## Migrationen

- Neue Migration = **neue** Datei `sql/NNN_beschreibung.sql` (nächste Nummer).
  Bestehende Dateien **nie** editieren — der Runner bricht bei Checksum-Drift ab.
- Ausführen passiert automatisch beim Deploy; manuell:
  ```
  docker compose run --rm migrate
  ```
- Zustand einsehen: `SELECT * FROM _meta._migrations ORDER BY applied_at;`
- Idempotent: erneuter Lauf ohne neue Dateien = „Keine neuen Migrationen."

---

## Backup

- Nächtlich als **Coolify Scheduled Task** einrichten:
  ```
  docker compose run --rm backup
  ```
- Ablage: Volume `backups` → `warehouse_<datum>_<zeit>.dump` (Format custom).
- Retention: `BACKUP_RETENTION_DAYS` (Default 14).
- Der Task prüft jedes Dump mit `pg_restore --list` (grobe Integrität).
- **Metabase-App-DB:** wird von Coolif­y separat gesichert (Coolify-eigene
  DB-Backups aktivieren). Enthält Dashboards/Fragen.

### Restore (🧑 einmal testen!)

Ein nie zurückgespieltes Backup ist kein Backup. Test z. B. in eine
Wegwerf-DB:
```
createdb -h <host> -U <admin> warehouse_restore_test
pg_restore -h <host> -U <admin> -d warehouse_restore_test \
  --clean --if-exists /backups/warehouse_<datum>.dump
# stichprobenartig zählen, dann:
dropdb -h <host> -U <admin> warehouse_restore_test
```

---

## Phase 2 — Pipedrive-Extraktion

- **Extraktion** (im Coolify-Container, Pipedrive-Secrets gesetzt):
  ```
  npm run extract:orgs      # Organisationen -> raw.pipedrive_organizations
  npm run extract:deals     # Deals (inkrementell) -> raw.pipedrive_deals
  ```
  Beide inkrementell über `raw._sync_state`. Erststart = Vollabzug.
- **core/marts** sind Views über `raw` — kein Transform-Schritt, immer aktuell.
- **Golden-Test nach jedem ETL-Lauf** (read-only, produktionssicher):
  ```
  npm run test:golden       # assertet 20 bekannte Deals gegen fixtures/golden-deals.json
  ```
  Schlägt er fehl, hat sich die Semantik verschoben → **nicht** ignorieren.
- **Lokale Entwicklung ohne Pipedrive:** `ALLOW_LOAD_GOLDEN=1 npm run load:golden`
  lädt die Fixtures in `raw` (leert `raw.pipedrive_deals` — nur lokal!).
- **Benötigte Secrets** zusätzlich: `PIPEDRIVE_API_TOKEN` (read-only),
  `PIPEDRIVE_COMPANY_DOMAIN`.

## Troubleshooting

| Symptom | Ursache / Fix |
|---|---|
| `migrate` bricht mit „Fehlt: Umgebungsvariable" ab | Secret nicht gesetzt. |
| `getaddrinfo … WAREHOUSE_DB_HOST` | Ressource hängt nicht im selben Netz wie Postgres. |
| „Drift: NNN_….sql wurde verändert" | Migration nachträglich editiert — stattdessen neue Datei. |
| `permission denied for schema raw` bei metabase_ro | **Korrekt so** (DSGVO). |
| Backup `pg_dump: server version mismatch` | `PG_MAJOR` ≠ Server-Major → Image-Tag anpassen. |
