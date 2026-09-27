#!/bin/sh
set -eu
# Runs once on a new local PostgreSQL volume. psql quotes the random password.
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1 \
  --set runtime_password="$PALMY_DB_RUNTIME_PASSWORD" <<'SQL'
CREATE ROLE palmy_runtime LOGIN PASSWORD :'runtime_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE palmy FROM PUBLIC;
GRANT CONNECT ON DATABASE palmy TO palmy_runtime;
SQL
