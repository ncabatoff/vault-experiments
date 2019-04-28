#!/usr/bin/env bash

set -e

cd $(dirname $0)/client
GOOS=linux go build

cd $(dirname $0)
docker-compose rm -fs
docker-compose up -d
