#!/usr/bin/env bash

# Assumes $VAULT_ADDR's root token is in $VAULT_TOKEN.

set -e

tmpdir=`mktemp -d /tmp/vaultXXXXXX`

vault secrets enable transit
vault write -force /transit/keys/vault2_autounseal

cat - > $tmpdir/primary-policy.hcl <<EOF
path "/transit/encrypt/vault2_autounseal" {
	capabilities = ["update"]
}
path "/transit/decrypt/vault2_autounseal" {
	capabilities = ["update"]
}
EOF
vault policy write secautounseal $tmpdir/primary-policy.hcl

cat - > $tmpdir/vault-secondary.hcl <<EOF
ui = true

listener "tcp" {
    address = "0.0.0.0:8202"
    tls_disable = 1
}

storage "consul" {
    path = "vault2/"
}

seal "transit" {
  address            = "$VAULT_ADDR"
  disable_renewal    = "false"
  key_name           = "vault2_autounseal"
  mount_path         = "transit/"
}
EOF

SEC_TOKEN=$(vault token create -policy=secautounseal -format=json |jq -r .auth.client_token)

VAULT_TOKEN=$SEC_TOKEN vault server -config=$tmpdir/vault-secondary.hcl -log-level=debug > $tmpdir/secondary.log 2>&1 &

while ! nc -z localhost 8202; do
  sleep 1
  echo -n '.'
done
echo
vault2_root_token=$(VAULT_TOKEN=$SEC_TOKEN VAULT_ADDR=http://localhost:8202 vault operator init -key-shares=1 -key-threshold=1 -format=json|jq -r .root_token)
VAULT_ADDR=http://localhost:8202 VAULT_TOKEN=$vault2_root_token vault secrets enable kv
VAULT_ADDR=http://localhost:8202 VAULT_TOKEN=$vault2_root_token vault kv put kv/foo val=1

kill %1
while nc -z localhost 8202; do
  sleep 1
  echo -n '.'
done
echo

VAULT_TOKEN=$SEC_TOKEN vault server -config=$tmpdir/vault-secondary.hcl -log-level=debug > $tmpdir/secondary-unseal.log 2>&1 &
function cleanup {
  kill %1
  rm -rf $tmpdir
  vault secrets disable transit
  vault policy delete secautounseal
  consul kv delete -recurse vault2
}
trap cleanup EXIT
while ! nc -z localhost 8202; do
  sleep 1
  echo -n '.'
done
echo

VAULT_ADDR=http://localhost:8202 VAULT_TOKEN=$vault2_root_token vault kv get kv/foo
