#!/bin/bash
set -e

# Create SonarQube database and user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER sonarqube WITH ENCRYPTED PASSWORD '${SONARQUBE_DB_PASSWORD:-sonarqube}';
    CREATE DATABASE sonarqube OWNER sonarqube;
    GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonarqube;
EOSQL
