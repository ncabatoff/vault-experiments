#!/usr/bin/env bash

# Assumes $VAULT_ADDR's root token is in $VAULT_TOKEN.

set -e

tmpdir=`mktemp -d /tmp/vaultXXXXXX`

vault policy delete badapp 2>/dev/null || true
cat - > $tmpdir/badapp-policy.hcl <<EOF
path "/auth/token/renew-self" {
	capabilities = ["update"]
}
EOF
vault policy write badapp $tmpdir/badapp-policy.hcl

VAULT_TOKEN=$(vault token create -policy=badapp -renewable -ttl=10m -field=token)
/vagrant/cmd/badapp/badapp