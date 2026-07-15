# ADR 0001 — Stack-Auswahl

**Status:** akzeptiert (aus Build-Auftrag übernommen)
**Datum:** 2026-07

## Kontext

Ein Kfz-Sachverständigenbüro braucht ein Data Warehouse + BI-Layer, das
Entscheidungen stützt (zehn Leitfragen, siehe `CLAUDE.md`). Bestehende
Infrastruktur: n8n + Coolify (selbst gehostet), M365. Marginale Kosten sollen
≈ 0 bleiben.

## Entscheidung

```
Quellen ──> ELT (TypeScript, Cron-Container) ──> PostgreSQL (raw/core/marts) ──> Metabase OSS
```

- **TypeScript** für die Extraktoren, weil der Bestandscode (n8n Code-Nodes)
  JavaScript ist.
- **PostgreSQL** als Warehouse, drei Schemata `raw` / `core` / `marts`.
- **Transformation als nummerierte SQL-Migrationen + Views**, kein dbt.
- **Metabase OSS** als BI-Layer, mit eigener App-Datenbank (getrennt vom
  Warehouse).
- **n8n** bleibt für Ereignisgetriebenes (Mail-Eingang → Abrechnungs-Pipeline).

## Bewusst verworfen

- **dbt** — Overhead bei dieser Größe. SQL-Views reichen, bis es >20 Modelle
  sind. Wird neu bewertet, wenn diese Grenze erreicht ist.
- **Power BI / Cloud-Warehouses (BigQuery, Snowflake) / Airflow** — laufende
  Kosten und Betriebslast ohne Gegenwert bei dieser Datenmenge.

## Konsequenzen

- Alles läuft auf dem vorhandenen Coolify → keine neuen Fixkosten.
- Der Preis ist Handarbeit bei Orchestrierung (Cron statt Airflow) und
  Transformation (SQL statt dbt-Modelle). Bei dieser Größe akzeptabel.
