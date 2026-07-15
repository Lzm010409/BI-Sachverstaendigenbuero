-- 00-bootstrap-roles.sql
--
-- EINMALIG von Hand auszuführen, mit einem Admin/Superuser der BESTEHENDEN
-- PostgreSQL-Instanz (das Admin-Passwort kommt in KEIN App-Secret).
-- Legt die beiden DB-Rollen und die Warehouse-Datenbank an. Danach übernimmt
-- der Migrations-Runner (läuft als `etl`).
--
-- Platzhalter <...> vor dem Ausführen durch echte, starke Passwörter ersetzen
-- (dieselben Werte, die als Coolify-Secrets bzw. in Metabase hinterlegt werden).
--
--   psql "postgresql://<admin>:<admin_pw>@<host>:5432/postgres" -f 00-bootstrap-roles.sql

-- Rolle für ETL + Transformation: schreibt raw, liest/schreibt core, baut marts.
CREATE ROLE etl LOGIN PASSWORD '<ETL_DB_PASSWORD>';

-- Read-only Rolle für Metabase-Datenquelle: liest später nur core + marts.
CREATE ROLE metabase_ro LOGIN PASSWORD '<METABASE_RO_PASSWORD>';

-- Warehouse-Datenbank, getrennt von Metabases App-DB. Owner = etl, damit der
-- Migrations-Runner Schemas anlegen darf.
CREATE DATABASE warehouse OWNER etl;

-- metabase_ro darf sich mit der Warehouse-DB verbinden (Objektrechte kommen aus
-- der Migration 001_init.sql; raw bleibt gesperrt).
GRANT CONNECT ON DATABASE warehouse TO metabase_ro;
