---
name: rds-postgres-permissions
description: Use when managing PostgreSQL user permissions on AWS RDS, or checking vacuum/bloat health.
---

# RDS PostgreSQL Permission Management

## When to Use
- Audit a PostgreSQL user's permissions (roles, databases, tables, schemas)
- Grant/revoke DML or DDL access on RDS databases
- Diagnose "permission denied" errors on RDS Postgres
- Review role memberships and inherited privileges

## Connecting via Vault (no plaintext credentials)

Never paste DB passwords in chat. Store creds in Vault, source at connection time.

### Store once
```bash
VAULT_ADDR=https://vault.internal.gift.id vault kv put secret/rds/leadgen \
  host="<endpoint>" port="5432" database="<db>" username="<user>" password="<password>"
```

### Connect each session (password never in chat)
```bash
export VAULT_ADDR=https://vault.internal.gift.id
export PGPASSWORD=$(vault kv get -field=password secret/rds/leadgen)
HOST=$(vault kv get -field=host secret/rds/leadgen)
PORT=$(vault kv get -field=port secret/rds/leadgen)
DB=$(vault kv get -field=database secret/rds/leadgen)
USER=$(vault kv get -field=username secret/rds/leadgen)
psql "host=$HOST port=$PORT dbname=$DB user=$USER" -c "SELECT 1;"
```

### Prerequisites
- Vault CLI installed (`brew install vault`)
- `VAULT_ADDR` set to Vault URL
- Valid token in `~/.vault-token` (check with `vault token lookup`)
- OIDC tokens expire in 1h — re-auth with `vault login` when expired
- Token needs `superadmin` or equivalent policy for KV read/write

### Pitfall: expired Vault token
`vault token lookup` returns 403 when token expired. Re-auth before retrying. Don't store tokens in memory — they expire.

See `references/vault-credential-workflow.md` for full setup details.

Known Vault paths for DB credentials:
- `secret/rds/staging-db` — staging RDS (host, port, database, username, password)
- `secret/rds/leadgen` — leadgen DB
- `database/roles/readonly` — dynamic readonly creds (PostgreSQL role-based, TTL 1h)

## Connecting to RDS PostgreSQL (legacy inline)
Use `psql` with `PGPASSWORD` env var (never inline password in connection string for logging safety):

```bash
PGPASSWORD='<password>' psql "host=<rds-endpoint> port=5432 dbname=<db> user=<user>" -c "<query>"
```

**Security:** If password was exposed in chat, rotate it after session. Store in Vault going forward.

## Auditing User Permissions

### 1. Role properties (superuser, login, etc.)
```sql
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, rolbypassrls, rolconnlimit
FROM pg_roles WHERE rolname = '<user>';
```
**Pitfall:** `rolexpires` column does NOT exist in standard pg_roles. Don't include it.

### 2. Role memberships (inherited privileges)
```sql
SELECT r.rolname AS role, m.rolname AS member_of
FROM pg_auth_members a
JOIN pg_roles r ON r.oid = a.roleid
JOIN pg_roles m ON m.oid = a.member
WHERE m.rolname = '<user>';
```

### 3. Database-level access
```sql
SELECT datname,
       has_database_privilege('<user>', datname, 'CONNECT') AS can_connect,
       has_database_privilege('<user>', datname, 'CREATE') AS can_create,
       has_database_privilege('<user>', datname, 'TEMPORARY') AS can_temp
FROM pg_database WHERE datistemplate = false ORDER BY datname;
```

### 4. Table-level privileges (RELIABLE method)
Use `has_table_privilege()` — more reliable than `information_schema.role_table_grants` which can return 0 rows even when privileges exist (especially with inherited role grants):

```sql
SELECT n.nspname AS schema, c.relname AS table,
       has_table_privilege('<user>', c.oid, 'SELECT') AS sel,
       has_table_privilege('<user>', c.oid, 'INSERT') AS ins,
       has_table_privilege('<user>', c.oid, 'UPDATE') AS upd,
       has_table_privilege('<user>', c.oid, 'DELETE') AS del
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog','information_schema')
ORDER BY n.nspname, c.relname;
```

### 5. List all databases
```sql
SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;
```

### 6. List all tables/views in non-system schemas
```sql
SELECT n.nspname, c.relname, c.relkind
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog','information_schema')
  AND n.nspname NOT LIKE 'pg_toast%'
  AND n.nspname NOT LIKE 'rds%'
  AND c.relkind IN ('r','v','m','p')
ORDER BY n.nspname, c.relname;
```

## Granting DML Access (SELECT/INSERT/UPDATE/DELETE)

**Pitfall:** `psql -c "DO $$ ... $$"` FAILS — dollar-quoting breaks when passed via `-c`. Always use `psql -f <file>` for DO blocks with `$$`.

### Step 1: Use the template script
Copy `scripts/grant_dml.sql`, replace `<TARGET_USER>`, then run via `-f`.
Full inline version for reference:
```bash
cat <<'SQL' > /tmp/grant_user.sql
DO $$
DECLARE
    s text;
BEGIN
    FOREACH s IN ARRAY ARRAY(
        SELECT nspname FROM pg_namespace
        WHERE nspname NOT IN ('pg_catalog','information_schema')
          AND nspname NOT LIKE 'pg_toast%'
          AND nspname NOT LIKE 'rds%'
    )
    LOOP
        EXECUTE format('GRANT USAGE ON SCHEMA %I TO <user>', s);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO <user>', s);
        EXECUTE format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA %I TO <user>', s);
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <user>', s);
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT USAGE, SELECT ON SEQUENCES TO <user>', s);
    END LOOP;
END $$;
SQL
```

### Step 2: Execute
```bash
PGPASSWORD='<password>' psql "host=<endpoint> port=5432 dbname=<db> user=<admin>" -f /tmp/grant_user.sql
```

### Step 3: Verify with has_table_privilege (see step 4 above)

## Key Concepts
- `GRANT ... ON ALL TABLES IN SCHEMA` applies to existing tables only
- `ALTER DEFAULT PRIVILEGES` ensures future-created tables auto-grant to the user
- `GRANT USAGE ON SCHEMA` is required before table-level grants in that schema work
- `GRANT USAGE, SELECT ON SEQUENCES` needed for INSERT on tables with serial/identity columns
- RDS: `rdsadmin` database is internal — users typically can't connect
- `rds_iam` role enables IAM auth (separate from password auth)
- Filter out `rds%` schemas — internal to RDS

## Vacuum and Bloat Analysis

Check if manual VACUUM needed across all databases on an instance.

### 1. Check autovacuum settings
```sql
SHOW autovacuum;
SHOW track_counts;
SELECT name, setting FROM pg_settings
WHERE name IN ('autovacuum','autovacuum_vacuum_threshold','autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_threshold','autovacuum_analyze_scale_factor','autovacuum_naptime');
```

### 2. Scan all databases for dead tuples + vacuum history
Reusable script: `scripts/vacuum-check.sh` — iterates all non-template DBs, queries `pg_stat_user_tables` for dead tuples, dead/live ratio, last autovacuum, and autovacuum run count.

Key query per database (also catches bloated tables with 0 dead tuples):
```sql
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
```

### 3. Assess: autovacuum threshold calculation
Autovacuum triggers when: `n_dead_tup > autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor * n_live_tup`

With defaults (threshold=50, scale_factor=0.2): a table with 120K live tuples needs >24069 dead tuples to trigger. If dead count exceeds this, autovacuum should kick in within `autovacuum_naptime` (default 60s).

### 4. Decision criteria
- **No manual VACUUM needed**: autovacuum ON, recent `last_autovacuum` timestamps present, dead tuple counts below or near threshold.
- **Manual VACUUM ANALYZE warranted**: tables with high dead_pct (>100%) AND `autovacuum_count=0` AND dead tuples well above threshold — clears dead tuples, updates planner stats. Does NOT shrink files.
- **VACUUM FULL warranted**: table has significant bloat (large `pg_total_relation_size` relative to live rows, e.g. 49 GB table with 1 live row). VACUUM FULL rewrites table to disk and reclaims space. **Locks table exclusively** — OK for staging, risky for prod.
- **Force single table**: `VACUUM (ANALYZE) <schema>.<table>;` for dead tuples, `VACUUM FULL <schema>.<table>;` for disk reclaim.

### 5. VACUUM FULL: when and how
- VACUUM (non-FULL): clears dead tuples, marks space reusable for new rows. File size unchanged. No lock.
- VACUUM FULL: rewrites entire table, reclaims disk space back to OS. **Exclusive lock** on table — blocks all reads/writes.
- Use VACUUM FULL on staging when tables have massive bloat (e.g. autovacuum ran many times but table never shrank). On prod, schedule during maintenance window or use `pg_repack` (no exclusive lock).
- After VACUUM FULL, run `ANALYZE` to update planner stats (VACUUM FULL does this automatically if called as `VACUUM FULL ANALYZE`).

### 6. Bulk scan across all databases
When asked to check vacuum health across an entire instance, use `execute_code` with subprocess to iterate all non-template DBs. Filter for tables that are either large (>100 MB) or have significant dead tuples (>1000). See `references/bulk-vacuum-workflow.md` for the full approach.

### Pitfall: stale stats
`pg_stat_user_tables` counters accumulate since last reset. High `autovacuum_count` with recent `last_autovacuum` = healthy. High dead tuples with `autovacuum_count=0` and no `last_autovacuum` = investigate (autovacuum may be disabled per-table via `ALTER TABLE ... SET (autovacuum_enabled=false)`).

### Pitfall: CamelCase table names
PostgreSQL folds unquoted identifiers to lowercase. Tables created with quoted CamelCase (e.g. `"Segments"`, `"Jobs"`) must ALWAYS be double-quoted in queries:
```sql
-- WRONG: VACUUM ANALYZE public.Segments;  → ERROR: relation does not exist
-- RIGHT:
VACUUM ANALYZE "public"."Segments";
```
Check exact names first: `SELECT '"'||schemaname||'"."'||relname||'"' FROM pg_stat_user_tables;`

### Pitfall: Vault MCP token not shared with CLI
The Vault MCP server (`mcp__vault__*`) requires its own token configured in Hermes config. It does NOT inherit `VAULT_TOKEN` from the shell. If MCP returns "vault token not provided for session", fall back to `vault` CLI with `VAULT_ADDR` + `VAULT_TOKEN` env vars set in terminal.

## DDL Access (create/alter/drop tables)
Grant CREATE on database:
```sql
GRANT CREATE ON DATABASE <dbname> TO <user>;
```
Or grant on specific schema:
```sql
GRANT CREATE ON SCHEMA <schema> TO <user>;
```

## Pitfalls
1. **Dollar-quoting with psql -c**: `DO $$` blocks fail via `-c`. Use `-f file.sql` instead.
2. **information_schema unreliability**: `role_table_grants` view may not show inherited privileges. Always verify with `has_table_privilege()`.
3. **rolexpires doesn't exist**: Standard pg_roles has no `rolexpires` column.
4. **Sequence permissions forgotten**: INSERT fails on tables with SERIAL columns if sequence USAGE not granted.
5. **Default privileges scope**: `ALTER DEFAULT PRIVILEGES` only affects tables created by the user executing the command — consider setting it for the table-owning role.
6. **zsh variable-with-spaces**: `PSQL="psql -h host -p 5432 -U user"; $PSQL -d db -c "..."` fails in zsh — it treats the entire string as a command name. Use a shell function or separate args (`psql -h "$H" -p "$P" ...`) instead. See `references/bulk-vacuum-workflow.md` § 8.
7. **execute_code 5-min timeout for bulk VACUUM FULL**: `execute_code` caps at 300s. VACUUM FULL on large tables (24 GB+) can take 4+ min each. For batches, use `terminal(background=true)` with a shell loop. See `references/bulk-vacuum-workflow.md` § 8.
