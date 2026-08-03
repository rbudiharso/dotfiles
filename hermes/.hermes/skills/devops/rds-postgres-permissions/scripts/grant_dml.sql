-- Grant DML (SELECT, INSERT, UPDATE, DELETE) to a PostgreSQL user
-- on all existing tables + sequences in all non-system schemas.
-- Also sets DEFAULT PRIVILEGES so future tables auto-grant.
--
-- Usage:
--   1. Replace <TARGET_USER> with the actual username
--   2. Run: psql -f grant_dml.sql (do NOT use -c, dollar-quoting breaks)
--   3. Verify with has_table_privilege() queries

DO $$
DECLARE
    s text;
    target_user text := '<TARGET_USER>';
BEGIN
    FOREACH s IN ARRAY ARRAY(
        SELECT nspname FROM pg_namespace
        WHERE nspname NOT IN ('pg_catalog','information_schema')
          AND nspname NOT LIKE 'pg_toast%'
          AND nspname NOT LIKE 'rds%'
    )
    LOOP
        EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', s, target_user);
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO %I', s, target_user);
        EXECUTE format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA %I TO %I', s, target_user);
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', s, target_user);
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT USAGE, SELECT ON SEQUENCES TO %I', s, target_user);
    END LOOP;
END $$;
