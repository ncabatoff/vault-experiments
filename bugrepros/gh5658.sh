#!/usr/bin/env bash

docker run --name vault --rm -d --cap-add=IPC_LOCK -p 127.0.0.1:8205:8200 -e VAULT_DEV_ROOT_TOKEN_ID=12345 vault:1.1.0
sleep 2
export VAULT_ADDR=http://127.0.0.1:8205
export VAULT_TOKEN=12345
vault auth enable userpass
vault auth enable approle
vault write auth/userpass/users/wildcard password=12345 policies=default,policies=default,approle-supervisor-wildcard
vault write auth/userpass/users/hardcode password=12345 policies=default,policies=default,approle-supervisor-hardcode
vault write auth/approle/role/my-app policies=default

vault policy write approle-supervisor-hardcode <(cat -<<EOF
path "auth/approle/role" {
  capabilities = ["list"]
}

path "auth/approle/role/my-app/secret-id" {
  capabilities = ["list"]
}

path "auth/approle/role/my-app/secret-id-accessor/lookup" {
  capabilities = ["update"]
}
EOF
)

vault policy write approle-supervisor-wildcard <(cat - <<EOF
path "auth/approle/role" {
  capabilities = ["list"]
}

path "auth/approle/role/+/secret-id" {
  capabilities = ["list"]
}

path "auth/approle/role/+/secret-id-accessor/lookup" {
  capabilities = ["update"]
}
EOF
)

vault write -force auth/approle/role/my-app/secret-id
#vault write -force auth/approle/role/my-app/secret-id
SECRET_ID_ACCESSOR=$(vault write -force -field=secret_id_accessor auth/approle/role/my-app/secret-id)
vault list auth/approle/role/my-app/secret-id

VAULT_TOKEN=

for u in hardcode wildcard; do
    echo user $u
    vault login -method=userpass username=$u password=12345
    for idx in {1..20}; do
      curl -sk -X POST -d "{\"secret_id_accessor\": \"$SECRET_ID_ACCESSOR\"}" \
        -H "X-Vault-Token: $(cat ~/.vault-token)" \
        $VAULT_ADDR/v1/auth/approle/role/my-app/secret-id-accessor/lookup
        sleep 0.1
    done
done

docker kill vault