# Bulk Vacuum Workflow

Complete workflow for checking vacuum health across all databases on a PostgreSQL instance, then running manual VACUUM on tables that need it.

## 1. Get credentials from Vault

```bash
export VAULT_ADDR=https://vault.internal.gift.id
export VAULT_TOKEN=<token>  # or use vault login -method=oidc

# Read staging DB creds
vault kv get secret/rds/staging-db
# Fields: host, port, database, username, password
```

Known Vault paths:
- `secret/rds/staging-db` — staging RDS (host, port, database, username, password)
- `secret/rds/leadgen` — leadgen DB
- `database/roles/readonly` — dynamic readonly creds (PostgreSQL role-based, TTL 1h)

## 2. Connect and verify

```bash
export PGPASSWORD='<from-vault>'
psql -h <host> -p <port> -U <user> -d postgres -c "SELECT 1;"
```

## 3. Scan all databases for bloat (via execute_code)

Use `execute_code` with subprocess to iterate all non-template DBs. For each DB, query tables with:
- `n_dead_tup > 1000` (significant dead tuples), OR
- `pg_total_relation_size > 100 MB` (large tables worth checking)

```python
import subprocess, os

env = os.environ.copy()
env['PGPASSWORD'] = '<password>'

# Get all DBs
result = subprocess.run(
    ['psql', '-h', '<host>', '-p', '5432', '-U', '<user>', '-d', 'postgres', '-A', '-t', '-c',
     "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;"],
    capture_output=True, text=True, env=env
)
dbs = [l.strip() for l in result.stdout.strip().split('\n') if l.strip()]

query = """
SELECT c.relname,
       pg_size_pretty(pg_total_relation_size(c.oid)),
       pg_total_relation_size(c.oid),
       s.n_dead_tup,
       s.n_live_tup,
       s.autovacuum_count,
       s.last_autovacuum
FROM pg_class c
JOIN pg_stat_user_tables s ON s.relname = c.relname
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND (s.n_dead_tup > 1000 OR pg_total_relation_size(c.oid) > 104857600)
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 10;
"""

for db in dbs:
    r = subprocess.run(
        ['psql', '-h', '<host>', '-p', '5432', '-U', '<user>', '-d', db, '-A', '-F', '|', '-c', query],
        capture_output=True, text=True, env=env, timeout=10
    )
    out = r.stdout.strip()
    if out and '(0 rows)' not in out:
        print(f"=== {db} ===")
        print(out)
        print()
```

## 4. Check autovacuum settings

```sql
SHOW autovacuum;
SHOW track_counts;
SELECT name, setting FROM pg_settings
WHERE name IN ('autovacuum','autovacuum_vacuum_threshold','autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_threshold','autovacuum_analyze_scale_factor','autovacuum_naptime');
```

Defaults: threshold=50, scale_factor=0.2, naptime=60s.
Autovacuum triggers when: `n_dead_tup > 50 + 0.2 * n_live_tup`.

## 5. Check per-table autovacuum disabled

```sql
SELECT c.relname, c.reloptions
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;
```

If `reloptions` contains `autovacuum_enabled=false`, autovacuum is disabled for that table.

## 6. Run manual VACUUM

### VACUUM ANALYZE (clears dead tuples, updates stats, no lock)
```sql
VACUUM ANALYZE "public"."TableName";
```

### VACUUM FULL (reclaims disk space, EXCLUSIVE LOCK)
```sql
VACUUM FULL "public"."TableName";
```

### Measure before/after
```sql
-- Before
SELECT pg_size_pretty(pg_total_relation_size('public."TableName"'));

-- Run VACUUM FULL

-- After
SELECT pg_size_pretty(pg_total_relation_size('public"."TableName"'));
```

## 7. Post-vacuum verification

```sql
SELECT
  c.relname,
  pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
  s.n_dead_tup AS dead,
  s.n_live_tup AS live,
  s.last_vacuum,
  s.last_analyze,
  s.vacuum_count,
  s.autovacuum_count
FROM pg_class c
JOIN pg_stat_user_tables s ON s.relname = c.relname
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;
```

## Key learnings from 2026-08-03 staging scan

- **Queues table (adira_worker_staging)**: 49 GB with 1 live row, 30 autovacuum runs. Autovacuum clears dead tuples but does NOT shrink files. Only VACUUM FULL reclaims space → 49 GB → 208 kB.
- **Segments + Jobs (adira_worker_staging)**: Never autovacuumed despite exceeding threshold. Stats were wildly stale (Segments showed 624 live, actual was 2,072,930). VACUUM ANALYZE corrected live tuple counts.
- **Stale stats pattern**: `n_live_tup` in `pg_stat_user_tables` can be very stale if ANALYZE never ran. After VACUUM ANALYZE, live count jumps to accurate value.
- **Bloat pattern across many DBs**: Multiple staging DBs had tables with 0 live rows but hundreds of MB to GB of size. These are candidates for VACUUM FULL on staging (not prod without maintenance window).

## 8. Bulk VACUUM FULL across many databases

When running VACUUM FULL on dozens of tables across many DBs, two constraints apply:

### Pitfall: execute_code 5-minute timeout
`execute_code` has a 300s hard timeout. VACUUM FULL on large tables (24 GB+) can take 4+ minutes each. A batch of 22+ tables will always exceed the cap. Use `terminal(background=true)` with a shell loop instead.

### Pitfall: zsh variable-with-spaces breaks psql
```bash
# WRONG — zsh treats entire string as single command name
PSQL="psql -h 10.31.2.210 -p 5432 -U root"
$PSQL -d mydb -c "SELECT 1"   # → zsh: command not found: psql -h 10.31.2.210 ...

# RIGHT — use a shell function
H=10.31.2.210; P=5432; U=root
vf() {
  local db=$1 table=$2
  local before=$(psql -h $H -p $P -U $U -d "$db" -A -t -c \
    "SELECT pg_total_relation_size('public.\"$table\"');" 2>/dev/null)
  [ -z "$before" ] && { echo "SKIP $db.$table"; return; }
  echo "=== $db.$table BEFORE: $((before/1048576))MB ==="
  psql -h $H -p $P -U $U -d "$db" -c "VACUUM FULL \"public\".\"$table\";" 2>&1
  local after=$(psql -h $H -p $P -U $U -d "$db" -A -t -c \
    "SELECT pg_total_relation_size('public.\"$table\"');" 2>/dev/null)
  echo "=== AFTER: $((after/1048576))MB (-$(( (before-after)/1048576 ))MB) ==="
}
```

### Batch strategy
- Split into batches: >1 GB tables (batch 1, slow) and 100 MB–1 GB tables (batch 2, faster).
- Run both as separate `terminal(background=true)` processes with `notify_on_complete=true`.
- Each table: measure before → VACUUM FULL → measure after → print reclaimed MB.
- Skip tables that return 0 or empty from `pg_total_relation_size` (may be wrong schema/name).
- Stale stats pattern: after VACUUM ANALYZE, `n_live_tup` can jump dramatically (e.g. 624 → 2,072,930) because stats were never gathered. This is expected, not a bug.
