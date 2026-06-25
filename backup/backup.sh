#!/bin/sh
# Backup runner for the PaddleOCR / Honcho stack.
#
# Every BACKUP_INTERVAL seconds (default 24h) it:
#   - dumps each Postgres database listed in POSTGRES_DBS to
#       /backups/postgres/<db>/<db>-<timestamp>.sql.gz
#   - streams a point-in-time Redis RDB snapshot to
#       /backups/redis/redis-<timestamp>.rdb
#   - prunes backups older than BACKUP_RETENTION_DAYS.
#
# It connects to the postgres/redis services over the compose network, so it
# needs no access to their data volumes.
set -eu

PGHOST="${PGHOST:-postgres}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
POSTGRES_DBS="${POSTGRES_DBS:-ocr honcho}"

REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-86400}"      # 24h
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
RUN_ONCE="${RUN_ONCE:-false}"                    # set true to back up once and exit

log() { echo "[backup $(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

backup_postgres() {
  ts="$1"
  for db in $POSTGRES_DBS; do
    dest_dir="$BACKUP_DIR/postgres/$db"
    mkdir -p "$dest_dir"
    out="$dest_dir/${db}-${ts}.sql.gz"
    log "pg_dump $db -> $out"
    if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" \
         --no-owner --no-privileges | gzip > "$out"; then
      log "ok $out ($(du -h "$out" | cut -f1))"
    else
      log "ERROR dumping $db; removing partial file"
      rm -f "$out"
    fi
  done
}

backup_redis() {
  ts="$1"
  dest_dir="$BACKUP_DIR/redis"
  mkdir -p "$dest_dir"
  out="$dest_dir/redis-${ts}.rdb"
  log "redis --rdb -> $out"
  # redis-cli --rdb triggers a SAVE on the server and streams the RDB to us.
  if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --rdb "$out" >/dev/null 2>&1; then
    log "ok $out ($(du -h "$out" | cut -f1))"
  else
    log "ERROR backing up redis; removing partial file"
    rm -f "$out"
  fi
}

prune() {
  [ "$BACKUP_RETENTION_DAYS" -gt 0 ] || return 0
  log "pruning backups older than ${BACKUP_RETENTION_DAYS} day(s)"
  find "$BACKUP_DIR/postgres" -type f -name '*.sql.gz' -mtime "+$BACKUP_RETENTION_DAYS" -delete 2>/dev/null || true
  find "$BACKUP_DIR/redis" -type f -name '*.rdb' -mtime "+$BACKUP_RETENTION_DAYS" -delete 2>/dev/null || true
}

run_once() {
  ts="$(date -u '+%Y%m%d-%H%M%S')"
  log "starting backup cycle ($ts)"
  backup_postgres "$ts"
  backup_redis "$ts"
  prune
  log "backup cycle complete"
}

while :; do
  run_once
  [ "$RUN_ONCE" = "true" ] && break
  log "sleeping ${BACKUP_INTERVAL}s until next backup"
  sleep "$BACKUP_INTERVAL"
done
