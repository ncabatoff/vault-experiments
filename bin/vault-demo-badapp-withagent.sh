#!/usr/bin/env bash

# Assumes $VAULT_ADDR's root token is in $VAULT_TOKEN.

set -e

tmpdir=`mktemp -d /tmp/vaultXXXXXX`
/vagrant/helpers/vault-agent $tmpdir warn '
path "/auth/token/renew-self" {
	capabilities = ["update"]
}
'

# Use Vault Agent with cache+auto-auth as our "Vault" server
VAULT_TOKEN=
VAULT_ADDR=http://localhost:8007

/vagrant/cmd/badapp/badapp