-- I-CCMS database roles (D-15, W-4). Idempotent. Run as the RDS master / a superuser:
--   psql "$MASTER_URL" -v ON_ERROR_STOP=1 \
--        -v app_password="$DB_APP_PASSWORD" -v migrator_password="$DB_MIGRATOR_PASSWORD" \
--        -f prisma/sql/roles.sql
-- iccms_migrator owns the schema objects (runs `prisma migrate deploy`).
-- iccms_app is what the api/worker use: DML only, and INSERT/SELECT only on trace_events.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iccms_migrator') THEN
    CREATE ROLE iccms_migrator LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'iccms_app') THEN
    CREATE ROLE iccms_app LOGIN;
  END IF;
END
$$;

-- Passwords are set outside the DO block because psql variables do not expand inside $$ bodies.
ALTER ROLE iccms_migrator PASSWORD :'migrator_password';
ALTER ROLE iccms_app PASSWORD :'app_password';

-- The master must be a member of iccms_migrator to run ALTER DEFAULT PRIVILEGES FOR ROLE.
GRANT iccms_migrator TO CURRENT_USER;

GRANT CONNECT ON DATABASE iccms TO iccms_migrator, iccms_app;
GRANT USAGE, CREATE ON SCHEMA public TO iccms_migrator;
GRANT USAGE ON SCHEMA public TO iccms_app;

-- Tables/sequences that iccms_migrator creates from now on.
ALTER DEFAULT PRIVILEGES FOR ROLE iccms_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO iccms_app;
ALTER DEFAULT PRIVILEGES FOR ROLE iccms_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO iccms_app;

-- Objects that already exist (re-running after migrations).
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO iccms_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO iccms_app;
REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM iccms_app;

-- W-4: trace_events is insert-only for the app.
DO $$
BEGIN
  IF to_regclass('public.trace_events') IS NOT NULL THEN
    REVOKE UPDATE, DELETE, TRUNCATE ON public.trace_events FROM iccms_app;
  END IF;
END
$$;
