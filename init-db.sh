#!/bin/bash
# Mounted into Postgres at /docker-entrypoint-initdb.d/ so it runs once on
# first DB init. Creates the second database (mem0_app) that the Mem0 server
# uses for auth/users/API-keys. The default POSTGRES_DB is used by pgvector
# for memory storage.

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE mem0_app'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mem0_app')\gexec
EOSQL
