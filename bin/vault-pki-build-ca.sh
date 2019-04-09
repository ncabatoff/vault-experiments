#!/usr/bin/env bash

set -e

policy=<<EOH
# Enable secrets engine
path "sys/mounts/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# List enabled secrets engine
path "sys/mounts" {
  capabilities = [ "read", "list" ]
}

# Work with pki secrets engine
path "pki*" {
  capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
}
EOH

# Step 1: Generate Root CA

vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki
vault write -field=certificate pki/root/generate/internal common_name="example.com" \
       ttl=87600h > CA_cert.crt
vault write pki/config/urls \
       issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
       crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"

openssl x509 -in CA_cert.crt -text
openssl x509 -in CA_cert.crt -noout -dates

# Step 2: Generate Intermediate CA

vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int
vault write -format=json pki_int/intermediate/generate/internal \
        common_name="example.com Intermediate Authority" ttl="43800h" \
        | jq -r '.data.csr' > pki_intermediate.csr
vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
        format=pem_bundle \
        | jq -r '.data.certificate' > intermediate.cert.pem
vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem

# Step 3: Create a Role

vault write pki_int/roles/example-dot-com \
        allowed_domains="example.com" \
        allow_subdomains=true \
        allowed_uri_sans="spiffe://example.com/foo" \
        allow_any_name=true \
        allowed_other_sans="1.3.6.1.2.1.27.1.1.2;UTF8:bar" \
        use_csr_sans=true \
        max_ttl="720h"

# Step 4: Request Certificates

vault write -format=json pki_int/issue/example-dot-com common_name="test.example.com" ttl="24h" > test.example.com.json

# Step 5: Revoke Certificates

vault write pki_int/revoke serial_number=$(jq -r .data.serial_number test.example.com.json)

# Step 6: Remove Expired Certificates

vault write pki_int/tidy tidy_cert_store=true tidy_revoked_certs=true
