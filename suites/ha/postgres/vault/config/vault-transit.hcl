pid_file = "/data/pid_file"

storage "file" {
  path = "/data/file"
}

listener "tcp" {
  address = "0.0.0.0:8210"
  tls_disable = true
}

telemetry {
  postgres_retention_time = "24h"
  disable_hostname = true
}