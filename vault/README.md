# Vault tools and config

These are mostly intended for use within the vagrant vm.

## initunseal

Does a 'vault operator init' and 'vault operator unseal', printing the root token and unseal key.

## init

Does a 'vault operator init' and saves the root token and unseal key in /etc/environment.

## unseal

Does a 'vault operator unseal' using keys from /etc/environment.

## standby

Creates a standby instance and unseals it using keys from /etc/environment.

## restandby

Wipes everything, then starts/inits/unseals a primary and a standby node.

## secondary

Creates a secondary cluster using performance replication.
