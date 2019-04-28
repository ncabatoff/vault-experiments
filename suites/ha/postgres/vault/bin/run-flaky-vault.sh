#!/bin/sh

# We claim this is a Bourne shell script (#!/bin/sh) but in fact we're using
# some bash-isms.  It seems the Alpine image we're running in uses Bash despite
# the name (and /bin/bash doesn't exist.)


# ------------ Consul -----------
cp /vault/config/vault-consul-service.json /consul/config
consul agent -client=0.0.0.0 -retry-interval=5s -retry-join=consul -data-dir=/consul/data -config-dir=/consul/config &

# ------------ Vault ------------
mkdir /config /data
PATH=$PATH:/vault/bin
export VAULT_ADDR=http://localhost:8200

echo "waiting for vault-transit"
while ! nc -z vault-transit 8210; do sleep 1; done
sleep 5

echo "starting vault"
vault server -config=/vault/config/vault-flaky.hcl &
while ! nc -z localhost 8200; do sleep 1; done

echo "initializing vault"
initoutput=$(vault operator init -key-shares=1 -key-threshold=1 -format=json)
ROOT_TOKEN=$(echo "$initoutput" | jq -r .root_token)

sleep 1

if [ "$1" != "" ]; then
  (VAULT_TOKEN=$ROOT_TOKEN eval "$1")
fi

echo "stopping vault"
kill $(cat /data/pid_file)
while nc -z localhost 8200; do sleep 1; done
sleep 1

echo "starting main loop"
while true; do
  vault server -config=/vault/config/vault-flaky.hcl &
  sleep $(( $RANDOM % 60 ))
  kill $(cat /data/pid_file)
  sleep $(( $RANDOM % 10 ))
done
