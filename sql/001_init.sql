-- 001_init.sql — Schemas, Rechte, Default Privileges
--
-- Läuft über den Migrations-Runner als Rolle `etl` (Owner der Warehouse-DB).
-- Idempotent. Voraussetzung: Rollen etl + metabase_ro und DB `warehouse`
-- existieren (siehe scripts/db/00-bootstrap-roles.sql).
--
-- DSGVO-Kernpunkt: metabase_ro erhält NUR Rechte auf core + marts, NIE auf raw.

-- --- Schemas ---------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS raw   AUTHORIZATION etl;
CREATE SCHEMA IF NOT EXISTS core  AUTHORIZATION etl;
CREATE SCHEMA IF NOT EXISTS marts AUTHORIZATION etl;

-- --- raw: dicht. Kein Zugriff für andere Rollen (enthält PII/Kennzeichen). --
REVOKE ALL ON SCHEMA raw FROM PUBLIC;
REVOKE ALL ON SCHEMA raw FROM metabase_ro;

-- --- core + marts: metabase_ro darf lesen ----------------------------------
GRANT USAGE ON SCHEMA core  TO metabase_ro;
GRANT USAGE ON SCHEMA marts TO metabase_ro;

-- Bereits existierende Objekte (bei erneutem Lauf) freigeben.
GRANT SELECT ON ALL TABLES IN SCHEMA core  TO metabase_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA marts TO metabase_ro;

-- Künftige Tabellen/Views, die `etl` in core/marts anlegt, automatisch für
-- metabase_ro lesbar machen.
ALTER DEFAULT PRIVILEGES FOR ROLE etl IN SCHEMA core
  GRANT SELECT ON TABLES TO metabase_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE etl IN SCHEMA marts
  GRANT SELECT ON TABLES TO metabase_ro;

-- Sicherstellen, dass metabase_ro NICHT versehentlich Schreibrechte über PUBLIC
-- erbt (defensiv; Objekte in core/marts).
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA core  FROM metabase_ro;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA marts FROM metabase_ro;
