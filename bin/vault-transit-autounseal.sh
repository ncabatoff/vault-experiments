#!/usr/bin/env bash

# Assumes $VAULT_ADDR's root token is in $VAULT_TOKEN.

set -e

tmpdir=`mktemp -d /tmp/vaultXXXXXX`

function setup_primary() {
    echo "* setup_primary"
    vault secrets disable transit >/dev/null 2>&1 || true
    vault secrets enable transit
    vault write -force /transit/keys/vault2_autounseal

    cat - > ${tmpdir}/primary-policy.hcl <<EOF
path "/transit/encrypt/vault2_autounseal" {
    capabilities = ["update"]
}
path "/transit/decrypt/vault2_autounseal" {
    capabilities = ["update"]
}
EOF
    vault policy write secautounseal ${tmpdir}/primary-policy.hcl
}

function setup_secondary() {
    echo "* setup_secondary: writing config tp ${tmpdir}"
    cat - > ${tmpdir}/vault-secondary.hcl <<EOF
pid_file = "${tmpdir}/pidfile"

listener "tcp" {
    address = "0.0.0.0:8202"
    tls_disable = 1
}

storage "file" {
    path = "${tmpdir}/vaultdata"
}

seal "transit" {
  address            = "${VAULT_ADDR}"
  disable_renewal    = "false"
  key_name           = "vault2_autounseal"
  mount_path         = "transit/"
}
EOF
}

function launch_secondary() {
    echo "* launch_secondary"
    vault server -config=${tmpdir}/vault-secondary.hcl -log-level=debug > ${tmpdir}/secondary.log 2>&1 &

    while ! nc -z localhost 8202; do
      sleep 1
      echo -n '.'
    done
    echo
}

function kill_secondary() {
    echo "* kill_secondary"
    kill $(cat ${tmpdir}/pidfile)

    while nc -z localhost 8202 || test -f ${tmpdir}/pidfile; do
      sleep 1
      echo -n '.'
    done
    sleep 1
    echo
}

function cleanup {
  kill_secondary
  #rm -rf ${tmpdir}
}

# ------------------------------------------------
# ------------- Script starts here ---------------
# ------------------------------------------------

trap cleanup EXIT

setup_primary

VAULT_TOKEN=$(vault token create -policy=secautounseal -field=token)

setup_secondary

VAULT_ADDR=http://localhost:8202

launch_secondary

VAULT2_ROOT_TOKEN=$(
  vault operator init -key-shares=1 -key-threshold=1 -format=json |
  jq -r .root_token)
VAULT_TOKEN=${VAULT2_ROOT_TOKEN} vault secrets enable kv
VAULT_TOKEN=${VAULT2_ROOT_TOKEN} vault kv put kv/foo val=1

kill_secondary
launch_secondary

VAULT_TOKEN=${VAULT2_ROOT_TOKEN} vault kv get kv/foo
