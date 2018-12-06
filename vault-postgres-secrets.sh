#!/bin/bash

# This script plays with the Vault PostgreSQL secrets engine.
# Dependencies: vault, postgres, jq, nc.
# Tested with Vault 1.0 and PG 10.6.

set -e

killall vault || true
killall postgres || true

# Start Postgres

PGDATA=/tmp/pg
PGPASS=rootpass
PGUSER=sa
PGDB=postgres
PGURLREST="localhost:5432/$PGDB?sslmode=disable"
rm -rf $PGDATA

echo "Creating PG DB"
echo $PGPASS | initdb --auth=md5 -U$PGUSER --pwfile=/dev/stdin $PGDATA > /dev/null

echo "Starting PG"
pg_ctl -D $PGDATA -l $PGDATA/pg.log start > $PGDATA/pgctl.out 2>&1

# Start Vault

export VAULT_ADDR=http://localhost:8200
ROOT_TOKEN=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)
echo -n "Starting Vault"
vault server -dev -dev-root-token-id="$ROOT_TOKEN" -log-level=DEBUG >/tmp/vault.log 2>&1 &
while ! nc -z localhost 8200; do sleep 1; echo -n .; done; echo
echo $ROOT_TOKEN | vault login -

# Configure Vault to talk to Postgres

vault secrets enable database

vault kv put database/config/my-postgresql \
    plugin_name=postgresql-database-plugin \
    allowed_roles="db-dba" \
    connection_url="postgresql://{{username}}:{{password}}@$PGURLREST" \
    username="$PGUSER" \
    password="$PGPASS"

TTL_SECONDS=5
vault kv put database/roles/db-dba \
    db_name="my-postgresql" \
    creation_statements="CREATE ROLE \"{{name}}\" WITH SUPERUSER LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';"
    revocation_statements="ALTER ROLE \"{{name}}\" NOLOGIN;"\
    renew_statements="ALTER ROLE \"{{name}}\" PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';"
    default_ttl="$TTL_SECONDS" \
    max_ttl="24h"

cat - > /tmp/db-dba.hcl << EOF
path "database/creds/db-dba" {
  capabilities = ["read"]
}
EOF

vault kv put sys/policy/db-dba policy=@/tmp/db-dba.hcl

DBA_TOKEN=$(vault token create -policy=db-dba -period=1h -field=token)
echo "$DBA_TOKEN" | vault login -
DBA_CREDS=$(vault kv get -format=json database/creds/db-dba | jq -r '.data.username + ":" + .data.password')
psql "postgresql://$DBA_CREDS@$PGURLREST" -c '\du'

sleep $(($TTL_SECONDS+1))
if psql "postgresql://$DBA_CREDS@$PGURLREST" -c '\du'; then
  echo "ERROR: able to connect to PG with creds that should be expired ($DBA_CREDS)" 1>&2
  exit 1
fi

echo --- DONE