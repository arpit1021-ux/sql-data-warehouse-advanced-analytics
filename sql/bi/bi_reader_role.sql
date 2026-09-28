/*
===============================================================================
BI Access: read-only role for reporting tools
===============================================================================
Script Purpose:
    Creates a least-privilege login that Power BI (or any BI tool) uses to
    read the Gold layer. It can SELECT from gold only - no access to the
    bronze/silver/etl schemas and no write permissions.

Usage:
    Run after the Gold layer is built, in the warehouse database.
    Replace the password before running it outside local development:
        psql -d DataWarehouse -v bi_password=s3cret -f sql/bi/bi_reader_role.sql
    (without -v the password defaults to 'change_me').
===============================================================================
*/

\if :{?bi_password}
\else
    \set bi_password change_me
\endif

SELECT format('CREATE ROLE bi_reader LOGIN PASSWORD %L', :'bi_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bi_reader')
\gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO bi_reader', current_database())
\gexec

GRANT USAGE  ON SCHEMA gold TO bi_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO bi_reader;        -- includes views
GRANT EXECUTE ON FUNCTION gold.month_diff(DATE, DATE) TO bi_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold GRANT SELECT ON TABLES TO bi_reader;
