#!/usr/bin/env bash

# Assumes $VAULT_ADDR's root token is in $VAULT_TOKEN.

set -x
set -e

tmpdir=`mktemp -d /tmp/vaultXXXXXX`

function setup_approle {
    vault auth enable approle || true

    vault policy write autoauth <(cat - <<EOF
path "/transit/encrypt/vault2_autounseal" {
	capabilities = ["update"]
}

path "/transit/decrypt/vault2_autounseal" {
	capabilities = ["update"]
}

path "/auth/token/create" {
	capabilities = ["create", "update"]
}
EOF
)

    vault write auth/approle/role/autoauth-role \
      policies=autoauth \
      secret_id_ttl=10m \
      token_ttl=10m \
      token_max_ttl=30m

    vault read -field=role_id -format=yaml auth/approle/role/autoauth-role/role-id > $tmpdir/role_id
    vault write -f -field=secret_id -format=yaml auth/approle/role/autoauth-role/secret-id > $tmpdir/secret_id
}

function setup_agent {
    cat - > $tmpdir/vault-agent.hcl << EOF
    pid_file = "$tmpdir/agentpid"

    auto_auth {
        method {
            type = "approle"
            config = {
                role_id_file_path = "$tmpdir/role_id"
                secret_id_file_path = "$tmpdir/secret_id"
            }
        }
        sink {
            type = "file"
            config = {
                path = "$tmpdir/agent-token"
            }
        }
    }

    cache {
        use_auto_auth_token = true
    }

    listener "tcp" {
        address = "127.0.0.1:8007"
        tls_disable = true
    }
EOF
}

setup_approle
function disable_approle {
  vault auth disable approle
  vault policy delete autoauth
}
trap disable_approle EXIT

setup_agent
VAULT_TOKEN= vault agent -config $tmpdir/vault-agent.hcl &
function killagent {
  disable_approle
  kill $(cat $tmpdir/agentpid)
}
trap "disable_approle; killagent" EXIT

sleep 2

vault secrets enable transit || true
vault write -force /transit/keys/vault2_autounseal

cat - > $tmpdir/vault-secondary.hcl <<EOF
pid_file = "$tmpdir/vaultpid"

ui = true

listener "tcp" {
    address = "0.0.0.0:8202"
    tls_disable = 1
}

storage "consul" {
    path = "vault2/"
}

seal "transit" {
  address            = "http://localhost:8007"
  disable_renewal    = "false"
  key_name           = "vault2_autounseal"
  mount_path         = "transit/"
}
telemetry {
    prometheus_retention_time = "1h"
    disable_hostname = true
}
EOF

VAULT_TOKEN=$(cat $tmpdir/agent-token) vault server -config=$tmpdir/vault-secondary.hcl -log-level=debug > $tmpdir/secondary.log 2>&1 &
while ! nc -z localhost 8202; do
  sleep 1
  echo -n '.'
done
echo

vault2_root_token=$(VAULT_TOKEN=$SEC_TOKEN VAULT_ADDR=http://localhost:8202 vault operator init -key-shares=1 -key-threshold=1 -format=json|jq -r .root_token)
VAULT_ADDR=http://localhost:8202 VAULT_TOKEN=$vault2_root_token vault secrets enable kv
VAULT_ADDR=http://localhost:8202 VAULT_TOKEN=$vault2_root_token vault kv put kv/foo val=1

while kill $(cat $tmpdir/vaultpid); do
  sleep 1
  echo -n '.'
done
echo

VAULT_TOKEN=$(cat $tmpdir/agent-token) vault server -config=$tmpdir/vault-secondary.hcl -log-level=debug > $tmpdir/secondary-unseal.log 2>&1 &
function cleanup {
  killagent
  vault secrets disable transit
  consul kv delete -recurse vault2
  kill $(cat $tmpdir/vaultpid)
  # rm -rf $tmpdir
}
trap cleanup EXIT
while ! nc -z localhost 8202; do
  sleep 1
  echo -n '.'
done
echo

VAULT_ADDR=http://localhost:8202 VAULT_TOKEN=$vault2_root_token vault kv get kv/foo
