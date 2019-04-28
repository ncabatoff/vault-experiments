pid_file = "/data/pid_file"

storage "postgresql" {
  connection_url = "postgres://vault:vaultpass@postgres:5432/postgres?sslmode=disable"
  ha_enabled = "true"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = true
}

telemetry {
  postgres_retention_time = "24h"
  disable_hostname = true
}

seal "transit" {
  address            = "http://vault-transit:8210"
  tls_skip_verify    = "true"
  disable_renewal    = "false"
  mount_path         = "transit/"
  key_name           = "unseal-key"
}