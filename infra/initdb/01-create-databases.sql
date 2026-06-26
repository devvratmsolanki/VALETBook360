-- Vālet — Postgres cluster bootstrap.
--
-- Runs as POSTGRES_USER (valet, superuser) against POSTGRES_DB (valet_auth)
-- via docker-entrypoint-initdb.d.
--
-- IMPORTANT: docker-entrypoint-initdb.d ONLY runs when the pgdata volume is
-- empty on first init. However, to survive "add a new service DB to a live
-- volume" scenarios, every CREATE DATABASE here is IDEMPOTENT using the
-- \gexec pattern (SELECT ... WHERE NOT EXISTS ... \gexec), which is supported
-- by psql -f (the runner used by the postgres entrypoint).
--
-- HOW IT WORKS:
--   The SELECT returns the CREATE DATABASE string only if the DB does not
--   already exist. \gexec executes whatever the query returned — so if the DB
--   exists, nothing is executed; if it is new, it is created.
--
-- HOW TO ADD A NEW SERVICE DB TO A LIVE VOLUME (non-empty pgdata):
--   1. Add the new DB block to this file (copy the \gexec block below).
--   2. Run the script manually against the running postgres:
--        docker exec -i valet-postgres psql -U valet -d valet_auth \
--          < infra/initdb/01-create-databases.sql
--   3. The new DB is created; existing DBs are untouched (idempotent).
--   Alternatively: docker exec valet-postgres createdb -U valet <new_db_name>

-- transaction-service database (valet_auth is already created by POSTGRES_DB).
SELECT 'CREATE DATABASE valet_core'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'valet_core')
\gexec
