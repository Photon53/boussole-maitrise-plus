#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git docker.io docker-compose-v2
systemctl enable --now docker
mkdir -p /opt/boussole-dev
chmod 750 /opt/boussole-dev
echo "DEV host ready; application deployment requires a separate approved workflow." > /opt/boussole-dev/README
