#!/bin/sh

mkdir -p /data/file /config
/vault/bin/vault server -config=/vault/config/vault-transit.hcl &

sleep 3

PATH=$PATH:/vault/bin
export VAULT_ADDR=http://localhost:8210

initoutput=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
vault operator unseal $(echo "$initoutput" | jq -r .unseal_keys_hex[0])

export VAULT_TOKEN=$(echo "$initoutput" | jq -r .root_token)

vault secrets enable transit

vault write -force /transit/keys/unseal-key

cat - >/tmp/policy.hcl <<EOF
path "/transit/encrypt/unseal-key" {
    capabilities = ["update"]
}
path "/transit/decrypt/unseal-key" {
    capabilities = ["update"]
}
EOF

vault policy write use-unseal-key /tmp/policy.hcl

vault token create -policy=use-unseal-key -field=token -id=TOKEN-USE-UNSEAL-KEY

sleep 999999