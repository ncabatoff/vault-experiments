#!/usr/bin/env bash

set -e

docker kill grafana 2>/dev/null || true

mkdir -p ~/grafana/provisioning/{datasources,dashboards}
cat - > ~/grafana/provisioning/datasources/prometheus.yml <<EOF
apiVersion: 1

datasources:
- name: prom
  type: prometheus
  access: proxy
  orgId: 1
  url: http://localhost:9090
  isDefault: true
  version: 1
  editable: true
EOF

cat - > ~/grafana/provisioning/dashboards/dashboards.yml <<EOF
apiVersion: 1

providers:
- name: 'default'
  orgId: 1
  folder: 'static'
  type: file
  disableDeletion: false
  updateIntervalSeconds: 60
  editable: true
  options:
    path: /local/dashboards
EOF

cp -r /vagrant/dashboards ~/grafana/

docker run --net=host --name grafana --rm -d -v ~/grafana:/local --env GF_PATHS_PROVISIONING=/local/provisioning grafana/grafana:6.0.2
