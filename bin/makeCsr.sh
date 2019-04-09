#!/usr/bin/env bash

makeCsr() {
  dn="$1"; shift
  san="$1"; shift
  openssl req -new -newkey rsa:2048 -nodes -config <(cat <<END
[req]
prompt = no
distinguished_name = req_dn
req_extensions = req_ext
[req_dn]
${dn}
[req_ext]
subjectAltName = @san
[san]
${san}
END
) -keyout /dev/null 2>/dev/null
}

csrToVault() {
  JSON=$(jq -n --arg CSR "$1" '{csr: $CSR}')
  curl -s --header "X-Vault-Token: $VAULT_TOKEN" --data "$JSON" \
    "$VAULT_ADDR/v1/pki_int/sign/example-dot-com" |
    jq -r .data.certificate
}

csrToVault "$(makeCsr 'commonName = "foo"' 'IP = "10.0.0.2"
otherName = "1.3.6.1.2.1.27.1.1.2;UTF8:bar"')"
#echo "$cert"| openssl x509 -text -noout
#echo "$cert"| openssl asn1parse
