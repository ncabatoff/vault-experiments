#!/usr/bin/env bash

# Assumes VAULT_ADDR points to a virgin vault and VAULT_TOKEN is set to root token.

set -x

set -e

tmpdir=`mktemp -d /tmp/consulXXXXXX`

mkdir -p $tmpdir/{etc,data}
cat - > $tmpdir/etc/config.hcl <<EOF
datacenter = "dc1"
data_dir = "$tmpdir/data"
encrypt = "VWFfYzySTrNJOesyCb1EcA=="
server = true
bootstrap_expect = 1
addresses {
    http = "127.0.0.1 {{ GetPrivateIPs }}"
}
ports {
    dns = 8686
    http = 8585
    server = 8383
    serf_lan = 8303
    serf_wan = -1
}
EOF
export CONSUL_MASTER_TOKEN=7652ba4c-0f6e-8e75-5724-5e083d72cfe4
cat - > $tmpdir/etc/acl.json <<EOF
{
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "down_policy": "extend-cache",
    "tokens": {
      "master": "$CONSUL_MASTER_TOKEN"
    }
  }
}
EOF

/usr/local/bin/consul agent -config-dir=$tmpdir/etc > $tmpdir/consul.log 2>&1 &
function cleanconsul {
  kill %1
  rm -rf $tmpdir
  vault secrets disable consul
}
#trap cleanconsul EXIT

sleep 12
export CONSUL_HTTP_ADDR=http://127.0.0.1:8585

vault secrets enable consul
vault write consul/config/access \
  address=$CONSUL_HTTP_ADDR \
  token=$CONSUL_MASTER_TOKEN

vault secrets tune -default-lease-ttl=48h -max-lease-ttl=72h consul/
vault secrets list -detailed

CONSUL_HTTP_TOKEN=$CONSUL_MASTER_TOKEN consul acl policy create -name 'list-all-nodes' -rules 'node_prefix "" { policy = "read" }'
vault write consul/roles/my-role policies=list-all-nodes
vault read -format=json consul/creds/my-role > $tmpdir/consultoken.json

while true; do
  CONSUL_HTTP_TOKEN=`jq -r .data.token < $tmpdir/consultoken.json` consul members > $tmpdir/members.txt
  if grep -q '^jessie' $tmpdir/members.txt; then
    vault lease renew `jq -r .lease_id < $tmpdir/consultoken.json`
  else
    echo "error running consul members, hostname not found; output: "
    cat $tmpdir/members.txt
    break
  fi
  sleep 900
done

