ui = true
listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = 1
}
storage "consul" {
    path = "vault/"
}
telemetry {
    prometheus_retention_time = "1h"
    disable_hostname = true
}

