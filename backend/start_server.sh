#!/bin/bash

set -e

export PYTHONPATH=$(pwd)

init_medconb_db() {
    echo "Initializing medconb database..."
    if [[ -z "$db_medconb_connstr" ]]; then
        echo "Error: Database connection string (db_medconb_connstr) is not set."
        exit 1
    fi

    echo "Checking database connection..."
    if ! psql "$db_medconb_connstr" -c '\q' 2>/dev/null; then
        echo "Error: Unable to connect to the database."
        exit 1
    fi
    echo "Database connection successful."

    if [[ "$MEDCONB_INIT_DB" == "force" ]]; then
        echo "Force option detected, dropping schema"
        psql "$db_medconb_connstr" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
    fi

    echo "Running schema migration..."
    migrate -database "${db_medconb_connstr}?sslmode=disable" -path migrate up

    echo "Importing fixtures..."
    curr_version=$(migrate -database "${db_medconb_connstr}?sslmode=disable" -path migrate version 2>&1)
    if [[ -f "fixtures/${curr_version}_fixtures.sql" ]]; then
        psql "$db_medconb_connstr" -f "fixtures/${curr_version}_fixtures.sql"
    else
        echo "No fixtures file found for version ${curr_version}."
    fi

    echo "Database init successful."
}


init_ontology_db() {
    echo "Initializing ontologies database..."
    if [[ -z "$db_ontologies_connstr" ]]; then
        echo "Error: Database connection string (db_ontologies_connstr) is not set."
        exit 1
    fi

    echo "Checking database connection..."
    if ! psql "$db_ontologies_connstr" -c '\q' 2>/dev/null; then
        echo "Error: Unable to connect to the database."
        exit 1
    fi
    echo "Database connection successful."

    if [[ "$MEDCONB_INIT_DB" == "force" ]]; then
        echo "Force option detected, dropping schema"
        psql "$db_ontologies_connstr" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
    fi

    echo "Importing fixtures..."
    gunzip < "fixtures/ontologies.sql.gz" | psql "$db_ontologies_connstr"

    echo "Database init successful."
}

if [[ -n "$MEDCONB_INIT_DB" && ("$MEDCONB_INIT_DB" == "true" || "$MEDCONB_INIT_DB" == "force") ]]; then
    echo "Found MEDCONB_INIT_DB=$MEDCONB_INIT_DB"
    echo "Running db_init script"

    echo "Fetching database connection strings using Python..."
    db_conn_strings=$(PYTHONPATH=. python3 - <<EOF
from medconb.config import config
db_medconb_connstr = config["database"]["medconb"]["url"].get()
db_ontologies_connstr = config["database"]["ontologies"]["url"].get()
print(f"db_medconb_connstr='{db_medconb_connstr}'")
print(f"db_ontologies_connstr='{db_ontologies_connstr}'")
EOF
    )
    eval "$db_conn_strings"
    echo "Database connection strings fetched successfully."

    echo "Checking if the database has already been initialized."
    user_count=$(psql "$db_medconb_connstr" -t -c 'SELECT COUNT(*) FROM "user";' | xargs)
    db_initialized=$([[ "$user_count" -gt 0 ]] && echo true || echo false)

    if [[ "$MEDCONB_INIT_DB" == "force" || "$db_initialized" != "true" ]]; then
        init_medconb_db
        init_ontology_db
    else
        echo "Database is already initialized and force option is not set. Skipping initialization."
    fi
fi

python helper/build_ontology_assets.py

uvicorn --factory medconb:create_app $@
