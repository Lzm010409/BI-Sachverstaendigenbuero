#!/usr/bin/env sh
# backup.sh — nächtlicher pg_dump der Warehouse-DB, Retention 14 Tage.
#
# Als Coolify Scheduled Task auf dem backup-Service laufen lassen (nächtlich),
# oder manuell. pg_dump-Major muss = Server-Major sein (Image-Tag entsprechend).
#
# Erwartet: WAREHOUSE_DB_HOST/PORT/NAME, ETL_DB_USER, ETL_DB_PASSWORD.
set -eu

: "${WAREHOUSE_DB_HOST:?WAREHOUSE_DB_HOST fehlt}"
: "${WAREHOUSE_DB_NAME:?WAREHOUSE_DB_NAME fehlt}"
: "${ETL_DB_USER:?ETL_DB_USER fehlt}"
: "${ETL_DB_PASSWORD:?ETL_DB_PASSWORD fehlt}"
PORT="${WAREHOUSE_DB_PORT:-5432}"
DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"

mkdir -p "$DIR"
TS="$(date +%F_%H%M)"
OUT="$DIR/warehouse_${TS}.dump"

echo "pg_dump -> $OUT"
PGPASSWORD="$ETL_DB_PASSWORD" pg_dump \
  -h "$WAREHOUSE_DB_HOST" -p "$PORT" -U "$ETL_DB_USER" \
  -d "$WAREHOUSE_DB_NAME" \
  --format=custom --no-owner \
  -f "$OUT"

# Integrität grob prüfen (Datei nicht leer, Header lesbar).
PGPASSWORD="$ETL_DB_PASSWORD" pg_restore --list "$OUT" > /dev/null
echo "ok: $(du -h "$OUT" | cut -f1)"

# Retention.
find "$DIR" -name 'warehouse_*.dump' -mtime +"$RETENTION_DAYS" -delete
echo "Retention: Dumps älter als ${RETENTION_DAYS} Tage entfernt."
