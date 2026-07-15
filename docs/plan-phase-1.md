# Plan — Phase 1: Infrastruktur

**Status:** ENTWURF zum Gegenlesen. Kein Code, bis der Plan abgenommen ist.
**Ziel (aus Auftrag):** PostgreSQL und Metabase laufen auf Coolify, Migrationen
sind automatisiert, Backup läuft und ist einmal getestet.

> Dieser Plan ist der Arbeitsgegenstand der Phase. Bitte besonders die
> **offenen Entscheidungen** (Abschnitt 8) prüfen — davon hängt der Bau ab.

---

## 1. Zielbild

```
                 Coolify (Server in DE)
 ┌───────────────────────────────────────────────────────────┐
 │  [pg-warehouse]      PostgreSQL   Schemas raw/core/marts    │
 │        ▲  ▲                                                 │
 │        │  └──────────── metabase_ro (nur core+marts, SELECT)│
 │        │                         ▲                          │
 │   etl/migrate (DDL+DML)          │                          │
 │        │                    [metabase]  Metabase OSS        │
 │        │                         │                          │
 │  [pg-metabase]  PostgreSQL  ◄─────┘  (nur App-Metadaten)    │
 │   (eigene Instanz, getrennt vom Warehouse)                 │
 └───────────────────────────────────────────────────────────┘
        nur [metabase] ist öffentlich (Subdomain, TLS via Coolify-Proxy)
        pg-warehouse / pg-metabase bleiben im internen Docker-Netz
```

Zwei **getrennte** PostgreSQL-Instanzen (Empfehlung, siehe 8.2): eine fürs
Warehouse, eine für Metabases eigene Anwendungsdaten. Der Auftrag verlangt die
Trennung ausdrücklich („nicht die Warehouse-DB").

---

## 2. Komponenten (docker-compose Services)

| Service | Image (gepinnt) | Zweck | Öffentlich? |
|---|---|---|---|
| `pg-warehouse` | `postgres:17` | Warehouse-DB (raw/core/marts) | nein (intern) |
| `pg-metabase` | `postgres:17` | Metabase-App-DB | nein (intern) |
| `metabase` | `metabase/metabase:v0.50.x` | BI-Layer | **ja** (Subdomain+TLS) |
| `migrate` | eigenes Node-Image | einmaliger Migrations-Lauf beim Deploy | nein |
| `backup` | `postgres:17` + Cron | nächtlicher `pg_dump` | nein |

- Alle Images auf **feste Tags** pinnen (kein `latest`) — reproduzierbare Deploys.
- `depends_on` mit Healthchecks: `migrate` und `metabase` warten auf
  `service_healthy` der jeweiligen DB (`pg_isready`).
- Persistente Named Volumes: `pgdata_warehouse`, `pgdata_metabase`, `backups`.

---

## 3. Datenbank-Rollen (DSGVO-relevant)

| Rolle | Rechte | Begründung |
|---|---|---|
| `warehouse_owner` | Owner der DB + Schemas, DDL | führt Migrationen aus |
| `etl` | `USAGE` auf raw/core; `INSERT/UPDATE/DELETE/SELECT` auf raw+core | Extraktoren + Transformation |
| `metabase_ro` | `USAGE`+`SELECT` **nur** auf core+marts | **kein** Zugriff auf `raw` |

**Kernpunkt DSGVO:** `metabase_ro` bekommt **niemals** Rechte auf `raw`. Dort
liegen Kennzeichen und Freitexte mit Personenbezug. Metabase kann diese Daten
damit strukturell nicht anzeigen — nicht per Konvention, sondern per Grant.

- Rollen werden im **DB-Init** angelegt (`docker/initdb/`), Passwörter aus
  Coolify-Secrets (nie im Repo). Läuft nur beim ersten Cluster-Init.
- Schemas + Grants + `ALTER DEFAULT PRIVILEGES` (damit künftige Tabellen in
  core/marts automatisch `SELECT` für `metabase_ro` bekommen) kommen als
  **Migration** (versioniert, reproduzierbar).

---

## 4. Migrations-Runner

`scripts/migrate.ts` (TypeScript, Repo-Konvention), nutzt `pg`:

- Bootstrappt Tabelle **`_migrations`** (`filename`, `checksum`, `applied_at`).
- Liest `sql/*.sql`, **numerisch sortiert**.
- Wendet jede noch nicht angewandte Datei in **einer Transaktion** an, schreibt
  `filename` + `sha256(checksum)` + Zeitstempel.
- **Idempotent:** bereits angewandte Dateien werden übersprungen.
- **Drift-Schutz:** ändert sich der Checksum einer bereits angewandten Datei →
  Abbruch mit Fehler (verhindert stilles Verschieben der Semantik).
- Läuft als `migrate`-Service **beim Container-Start/Deploy**, exit 0 nach Erfolg.

### Migrationsdateien in Phase 1

- **`001_init.sql`** — `CREATE SCHEMA raw/core/marts`; `GRANT USAGE`; Grants für
  `etl` (raw+core) und `metabase_ro` (core+marts, SELECT); `ALTER DEFAULT
  PRIVILEGES`; explizites `REVOKE` von `raw` für `metabase_ro`.

> Hinweis zur Nummerierung: Der Auftrag nennt beispielhaft `001_raw.sql` /
> `002_core.sql`. Ich schlage vor, die reine Schema-/Rechte-Bootstrap-Migration
> als `001_init.sql` zu führen; die **Inhalte** von raw (Phase 2) und core
> (Phase 2) werden dann `002_raw.sql` / `003_core.sql`. So bleibt „Struktur"
> von „Inhalt" getrennt. Falls du die Auftrags-Namen 1:1 willst, ziehe ich die
> Grants in den DB-Init — bitte in 8.4 entscheiden.

---

## 5. Backup

`scripts/backup.sh`, als `backup`-Service mit Cron (nächtlich):

- `pg_dump -Fc` (custom format, komprimiert) der **Warehouse-DB** →
  `backups/warehouse_YYYY-MM-DD.dump`.
- Ebenso **Metabase-App-DB** (enthält Dashboards/Fragen — auch schützenswert).
- **Retention 14 Tage** (`find backups -mtime +14 -delete`).
- `pg_dump`-Version = Server-Major (darum `postgres:17`-Image für den Job).
- Backup steht **bevor** Daten drin sind (Auftrag).

**Restore (zu testen, 🧑 MENSCH):**
```
pg_restore --clean --if-exists -d "$WAREHOUSE_DB" backups/warehouse_YYYY-MM-DD.dump
```
Ein Backup, das nie zurückgespielt wurde, ist kein Backup — daher einmal
verifizieren (Abschnitt 7).

---

## 6. Dateien, die Phase 1 anlegt

```
docker-compose.yml                 # 5 Services, Healthchecks, Volumes, Netze
docker/initdb/00-roles.sh          # Rollen etl/metabase_ro (Passwörter aus ENV)
docker/migrate.Dockerfile          # schlankes Node-Image für migrate/ETL
sql/001_init.sql                   # Schemas, Grants, Default Privileges
scripts/migrate.ts                 # Migrations-Runner (idempotent, Drift-Schutz)
scripts/backup.sh                  # pg_dump + Retention
docs/RUNBOOK.md                    # (Auszug) Restore, Migrations-Reset, Lauf bricht
.env.example                       # erweitert um Metabase-/Rollen-/Admin-Secrets
```

Keine Fachdaten, keine Extraktoren — die kommen in Phase 2.

---

## 7. Definition of Done (Auftrag)

- [ ] `docker compose up` auf **leerer** Umgebung erzeugt den kompletten Stack.
- [ ] Metabase erreichbar (Subdomain, TLS), verbindet sich mit `metabase_ro`
      auf die Warehouse-DB.
- [ ] `metabase_ro` kann `raw` **nicht** lesen (negativ getestet).
- [ ] Migrations-Runner idempotent (zweiter Lauf = keine Änderung).
- [ ] Backup läuft nächtlich, Retention greift.
- [ ] 🧑 Backup **einmal wiederhergestellt und verifiziert**.

---

## 8. Offene Entscheidungen (brauche ich von dir, bevor ich baue)

**8.1 PostgreSQL-Major-Version.** Empfehlung **17** (langjährig erprobt, für ein
Warehouse wichtiger als Neuheit). 18 wäre möglich. → 17 ok?

**8.2 Metabase-App-DB: eigene Instanz oder eigene DB?** Empfehlung: **eigener
`pg-metabase`-Container** (volle Isolation, getrennte Backups, marginaler
Mehrverbrauch). Alternative: nur eine eigene *Datenbank* in derselben Instanz
(spart einen Container, koppelt aber Verfügbarkeit/Backup). → Container ok?

**8.3 Backup-Ziel.** Nur lokales Coolify-Volume, oder zusätzlich **offsite**
(z. B. verschlüsselt auf S3-kompatiblen DE-Speicher)? Lokales Volume allein
schützt nicht gegen Serververlust. → Wie hättest du es gern?

**8.4 Migrations-Nummerierung** (Abschnitt 4): `001_init.sql` separat (mein
Vorschlag) oder Grants in den DB-Init ziehen, um `001_raw.sql` freizuhalten?

**8.5 Subdomain** für Metabase (z. B. `bi.gollenstede.app`?) und Bestätigung,
dass die DB-Ports **nicht** nach außen exponiert werden.

## 9. 🧑 MENSCH-Aufgaben dieser Phase (aus Auftrag)

- [ ] Coolify-Ressourcen + Subdomain bereitstellen.
- [ ] Metabase-Adminaccount, DB-Passwörter als Coolify-Secrets setzen.
- [ ] Server steht in Deutschland (DSGVO) — bestätigen.
- [ ] Backup einmal wiederherstellen und verifizieren.
