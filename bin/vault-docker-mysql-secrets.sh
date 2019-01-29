#!/bin/bash

docker kill vault mariadb 2>/dev/null
killall vault 2>/dev/null
export VAULT_TOKEN=myroot
export VAULT_ADDR=http://localhost:8200

set -e

# Start mysql server
MYSQL_ROOT=R00tPassword
docker run -d --rm --name mariadb -p 3306:3306 -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT mariadb:10.3-bionic

# Start vault server
# docker run -d --rm --name vault -p 8200:8200 --link mariadb:mysql --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=myroot' vault
vault server -dev -dev-root-token-id="$VAULT_TOKEN" -log-level=DEBUG >/tmp/vault.log 2>&1 &

# Wait for servers to be ready
sleep 10
docker run -it --rm --link mariadb:mysql mariadb sh -c "exec mysql -hmariadb -P3306 -uroot -p$MYSQL_ROOT << EOF
GRANT ALL PRIVILEGES ON *.* TO 'vaultadmin'@'%' IDENTIFIED BY 'vaultadminpassword' WITH GRANT OPTION;
CREATE DATABASE app;
FLUSH PRIVILEGES;
EOF"

vault secrets enable database

# vault_mariadb_host=mariadb # for vault running in docker
vault_mariadb_host=localhost # for vault running locally
vault write database/config/db \
  plugin_name=mysql-database-plugin \
  allowed_roles="*" \
  connection_url="{{username}}:{{password}}@tcp($vault_mariadb_host:3306)/mysql" \
  username="vaultadmin" \
  password="vaultadminpassword" \

vault write database/roles/readonly \
  db_name=db \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT ON *.* TO '{{name}}'@'%';" \
  default_ttl=1h max_ttl=24h

vault write -force database/rotate-root/db
