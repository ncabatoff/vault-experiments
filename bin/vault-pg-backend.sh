#!/usr/bin/env bash

# Start a Vault on port 8432 using a PG backend.

set -e

docker kill postgres 2>/dev/null || true

tmpdir=`mktemp -d /tmp/vaultXXXXXX`

cat - > $tmpdir/vault-pg.hcl <<EOF
ui = true
listener "tcp" {
    address = "0.0.0.0:8432"
    tls_disable = 1
}
storage "postgresql" {
    connection_url = "postgres://vault:vaultpass@localhost:5432/vault?sslmode=disable"
}
telemetry {
    prometheus_retention_time = "1h"
    disable_hostname = true
}
EOF

docker run --rm -d --net host --name postgres -e POSTGRES_PASSWORD=vaultpass -e POSTGRES_USER=vault postgres
while ! nc -z localhost 5432; do sleep 1; echo -n .; done; echo

docker run -i --rm --net host postgres psql -h localhost -U vault -f /dev/stdin <<EOF
CREATE TABLE vault_kv_store (
  parent_path TEXT COLLATE "C" NOT NULL,
  path        TEXT COLLATE "C",
  key         TEXT COLLATE "C",
  value       BYTEA,
  CONSTRAINT pkey PRIMARY KEY (path, key)
);

CREATE INDEX parent_path_idx ON vault_kv_store (parent_path);
EOF

vault server -config=$tmpdir/vault-pg.hcl -log-level=debug >$tmpdir/vault.log 2>&1 &
while ! nc -z localhost 8432; do sleep 1; echo -n .; done; echo

export VAULT_ADDR=http://localhost:8432

initoutput=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
unsealkey=$(echo "$initoutput" | jq -r .unseal_keys_hex[0])
roottoken=$(echo "$initoutput" | jq -r .root_token)
vault operator unseal "$unsealkey"

echo VAULT_ROOT_TOKEN=$roottoken

