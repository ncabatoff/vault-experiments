#!/usr/bin/env bash

# Assumes VAULT_ADDR points to a virgin vault and VAULT_TOKEN is set to root token.

set -x

set -e

mkdir -p /tmp/agent

function setup_approle {
    vault auth enable approle

    cat - > /tmp/agent/policy.hcl <<EOF
path "/kv/*" {
	capabilities = ["sudo", "create", "read", "update", "delete", "list"]
}

path "/auth/token/create" {
	capabilities = ["create", "update"]
}
EOF
    vault policy write autoauth /tmp/agent/policy.hcl

    vault write auth/approle/role/autoauth-role \
      policies=autoauth \
      secret_id_ttl=10m \
      token_ttl=10m \
      token_max_ttl=30m

    vault read -field=role_id -format=yaml auth/approle/role/autoauth-role/role-id > /tmp/agent/role_id
    vault write -f -field=secret_id -format=yaml auth/approle/role/autoauth-role/secret-id > /tmp/agent/secret_id
}

function setup_agent {
    cat - > /tmp/agent/vault-agent.hcl << EOF
    pid_file = "./pidfile"

    auto_auth {
        method {
            type = "approle"
            config = {
                role_id_file_path = "/tmp/agent/role_id"
                secret_id_file_path = "/tmp/agent/secret_id"
            }
        }
        sink {
            type = "file"
            config = {
                path = "/tmp/agent/file-foo"
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
setup_agent

vault secrets enable kv
vault kv put kv/foo val=bar

unset VAULT_TOKEN
vault agent -config /tmp/agent/vault-agent.hcl &
function killagent {
  kill %1
}
trap killagent EXIT

sleep 2
test bar = "$(VAULT_ADDR=http://127.0.0.1:8007 vault read -format=json -field=data kv/foo|jq -r .val)"