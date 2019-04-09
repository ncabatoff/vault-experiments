# vault-experiments

This repo contains miscellaneous scripts and resources for playing with Vault.

To spin up a single Vault instance with a consul backend:

```bash
vagrant up
```

This will fetch consul and vagrant binaries from Hashicorp.  Optionally you can put consul 
or vault binaries under consul/ or vault/ respectively.  This is helpful when building from
source, e.g.

```bash
make -C ~/go/src/github.com/hashicorp/vault dev && 
  cp ~/go/src/github.com/hashicorp/vault/bin/vault vault/ &&
  vagrant provision --provision-with vault
```

or on MacOS:

```bash
XC_OSARCH=linux/amd64 make -C ~/go/src/github.com/hashicorp/vault dev && 
  cp ~/go/src/github.com/hashicorp/vault/bin/vault vault/ &&
  vagrant provision --provision-with vault
```

The provisioner scripts ensure that the application is stopped before deploying binaries, 
and also setup systemd wrappers.

Check the health of the system using 
```bash
systemctl status consul vault
vault status
consul watch -type=service -service=vault
```

Or use the web UIs, ports forwarded to http://localhost:18500/ui (consul) and http://localhost:18200/ui (vault)

## Unsealing

When you first login:

```bash
/vagrant/vault/initunseal
```

After a reboot or a restart of Vault:

```bash
/vagrant/vault/unseal
```

## Dashboards

To enable monitoring, after unsealing your vault:

```bash
sudo /vagrant/provision-node_exporter
sudo /vagrant/provision-prometheus
/vagrant/provision-grafana.sh
```

Then (after a few seconds to a minute for it to come up)
you can connect to [Grafana](http://admin:admin@localhost:3000) to see
dashboards, or [Prometheus](http://localhost:19090/targets) to see the status
of metrics collection.

