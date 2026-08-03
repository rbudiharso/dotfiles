#!/usr/bin/env bash
# Scan all non-template databases on a PostgreSQL instance for vacuum/bloat status.
# Requires: PGPASSWORD, PGHOST, PGPORT, PGUSER set (or use Vault credential sourcing).
#
# Usage:
#   export PGPASSWORD=$(vault kv get -field=password secret/rds/staging-db)
#   export PGHOST=$(vault kv get -field=host secret/rds/staging-db)
#   export PGPORT=$(vault kv get -field=port secret/rds/staging-db)
#   export PGUSER=$(vault kv get -field=username secret/rds/staging-db)
#   bash scripts/vacuum-check.sh
#
# Output: per-database top 5 tables by dead tuple count, plus autovacuum settings.

set -euo pipefail

BASE_PSQL="psql -h ${PGHOST:?} -p ${PGPORT:-5432} -U ${PGUSER:?} -A -F'|' -c"

echo "=== Autovacuum Settings (postgres db) ==="
psql -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" -d postgres -A -F'|' -c "
  SELECT name, setting FROM pg_settings
  WHERE name IN ('autovacuum','autovacuum_vacuum_threshold','autovacuum_vacuum_scale_factor',
                 'autovacuum_analyze_threshold','autovacuum_analyze_scale_factor','autovacuum_naptime');
" 2>&1

echo ""
echo "=== Per-Database Vacuum Status ==="

# Get all non-template databases
DATABASES=$(psql -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" -d postgres -A -t -c \
  "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>&1)

for db in $DATABASES; do
  echo "--- $db ---"
  psql -h "$PGHOST" -p "${PGPORT:-5432}" -U "$PGUSER" -d "$db" -A -F'|' -c "
    SELECT
      schemaname||'.'||relname AS table,
      pg_size_pretty(pg_total_relation_size(c.oid)) AS size,
      n_live_tup AS live,
      n_dead_tup AS dead,
      ROUND(n_dead_tup::numeric / NULLIF(n_live_tup,0) * 100, 1) AS dead_pct,
      last_autovacuum,
      last_vacuum,
      autovacuum_count,
      vacuum_count
    FROM pg_stat_user_tables s
    JOIN pg_class c ON c.relname = s.relname
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND (s.n_dead_tup > 0 OR pg_total_relation_size(c.oid) > 104857600)
    ORDER BY pg_total_relation_size(c.oid) DESC
    LIMIT 10;
  " 2>&1
  echo ""
done
