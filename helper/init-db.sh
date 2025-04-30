#!/usr/bin/bash

psql -v ON_ERROR_STOP=1 --username postgres --dbname "postgres" -c 'CREATE DATABASE medconb' || true
psql -v ON_ERROR_STOP=1 --username postgres --dbname "postgres" -c 'CREATE DATABASE ontologies' || true
