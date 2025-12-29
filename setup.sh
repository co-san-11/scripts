#!/bin/bash
set -Eeuo pipefail

# ============================================================
# GLOBALS & LOGGING
# ============================================================

LOG=/var/log/dev-bootstrap.log
exec > >(tee -a "$LOG") 2>&1

echo "================================================="
echo " DEV ENVIRONMENT FULL BOOTSTRAP (SAFE + COMPLETE)"
echo "================================================="

# ============================================================
# WAIT FOR CLOUD-INIT
# ============================================================

if command -v cloud-init >/dev/null; then
  echo "[*] Waiting for cloud-init..."
  cloud-init status --wait || true
fi

# ============================================================
# APT HARDENING
# ============================================================

echo "[*] Hardening APT..."
cat >/etc/apt/apt.conf.d/99-retries <<EOF
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::ForceIPv4 "true";
EOF

# ============================================================
# RETRY FUNCTION
# ============================================================

retry() {
  local n=1
  local max=5
  local delay=10
  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo "Retry $n/$max failed. Retrying in $delay seconds..."
        sleep $delay
      else
        echo "Command failed after $max attempts: $*"
        return 1
      fi
    }
  done
}

# ============================================================
# INPUT IPs
# ============================================================

read -p "Enter dev-1 IP: " DEV1_IP
read -p "Enter dev-2 IP: " DEV2_IP
read -p "Enter dev-3 IP: " DEV3_IP
read -p "Enter THIS node's IP: " THIS_IP

if [[ "$THIS_IP" == "$DEV1_IP" ]]; then
  NODE_ROLE="dev1"
elif [[ "$THIS_IP" == "$DEV2_IP" ]]; then
  NODE_ROLE="dev2"
elif [[ "$THIS_IP" == "$DEV3_IP" ]]; then
  NODE_ROLE="dev3"
else
  echo "ERROR: THIS NODE IP does not match dev IPs"
  exit 1
fi

echo "[*] Node role detected: $NODE_ROLE"

# ============================================================
# BASE PACKAGES
# ============================================================

retry apt update -y
retry apt install -y \
  curl wget unzip jq ca-certificates gnupg lsb-release \
  python3 python3-pip software-properties-common

# ============================================================
# DOCKER
# ============================================================

if ! command -v docker >/dev/null; then
  echo "[*] Installing Docker..."
  retry apt install -y docker.io
  systemctl enable --now docker
fi

# ============================================================
# CONSUL
# ============================================================

CONSUL_VERSION=1.17.0

if ! command -v consul >/dev/null; then
  echo "[*] Installing Consul..."
  retry wget https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
  unzip -o consul_${CONSUL_VERSION}_linux_amd64.zip
  mv consul /usr/local/bin/
  rm consul_${CONSUL_VERSION}_linux_amd64.zip
fi

mkdir -p /etc/consul.d /var/consul

cat >/etc/consul.d/consul.hcl <<EOF
datacenter = "dev"
data_dir = "/var/consul"
server = true
bootstrap_expect = 3
bind_addr = "${THIS_IP}"
retry_join = ["${DEV1_IP}", "${DEV2_IP}", "${DEV3_IP}"]
ui_config { enabled = true }
EOF

cat >/etc/systemd/system/consul.service <<EOF
[Unit]
Description=Consul
After=network.target

[Service]
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable consul || true
systemctl restart consul || true

# ============================================================
# NOMAD
# ============================================================

NOMAD_VERSION=1.8.0

if ! command -v nomad >/dev/null; then
  echo "[*] Installing Nomad..."
  retry wget https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip
  unzip -o nomad_${NOMAD_VERSION}_linux_amd64.zip
  mv nomad /usr/local/bin/
  rm nomad_${NOMAD_VERSION}_linux_amd64.zip
fi

mkdir -p /etc/nomad.d /opt/nomad

cat >/etc/nomad.d/nomad.hcl <<EOF
datacenter = "dev"
data_dir = "/opt/nomad"
bind_addr = "0.0.0.0"

server {
  enabled = true
  bootstrap_expect = 3
  server_join {
    retry_join = ["${DEV1_IP}", "${DEV2_IP}", "${DEV3_IP}"]
  }
}

client {
  enabled = true
}
EOF

cat >/etc/systemd/system/nomad.service <<EOF
[Unit]
Description=Nomad
After=network.target

[Service]
ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nomad || true
systemctl restart nomad || true

# ============================================================
# POSTGRESQL + PATRONI
# ============================================================

retry apt install -y postgresql postgresql-client
pip3 install patroni[consul]

mkdir -p /etc/patroni

cat >/etc/patroni/patroni.yml <<EOF
scope: dev-cluster
namespace: /service/
name: ${NODE_ROLE}

restapi:
  listen: ${THIS_IP}:8008
  connect_address: ${THIS_IP}:8008

consul:
  url: http://${THIS_IP}:8500

postgresql:
  listen: ${THIS_IP}:5432
  connect_address: ${THIS_IP}:5432
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/15/bin
  parameters:
    max_connections: 200
    shared_buffers: 2GB
    wal_level: replica
EOF

cat >/etc/systemd/system/patroni.service <<EOF
[Unit]
Description=Patroni
After=network.target consul.service

[Service]
User=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable patroni || true
systemctl restart patroni || true

# ============================================================
# TRAEFIK (dev-1 & dev-2)
# ============================================================

if [[ "$NODE_ROLE" == "dev1" || "$NODE_ROLE" == "dev2" ]]; then
  if ! command -v traefik >/dev/null; then
    TRAEFIK_VERSION=2.11.0
    retry wget https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz
    tar -xvf traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz
    mv traefik /usr/bin/
    rm traefik_${TRAEFIK_VERSION}_linux_amd64.tar.gz
  fi

  mkdir -p /etc/traefik

  cat >/etc/traefik/traefik.yml <<EOF
entryPoints:
  web:
    address: ":80"

providers:
  consulCatalog:
    exposedByDefault: false

api:
  dashboard: true
EOF

  cat >/etc/systemd/system/traefik.service <<EOF
[Unit]
Description=Traefik
After=network.target

[Service]
ExecStart=/usr/bin/traefik --configFile=/etc/traefik/traefik.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable traefik || true
  systemctl restart traefik || true
fi

# ============================================================
# OBSERVABILITY (dev-3)
# ============================================================

if [[ "$NODE_ROLE" == "dev3" ]]; then
  docker run -d --restart unless-stopped --name prometheus -p 9090:9090 prom/prometheus || true
  docker run -d --restart unless-stopped --name grafana -p 3000:3000 grafana/grafana || true
  docker run -d --restart unless-stopped --name loki -p 3100:3100 grafana/loki || true
fi

# ============================================================
# PROMTAIL (ALL)
# ============================================================

docker run -d --restart unless-stopped \
  --name promtail \
  -v /var/log:/var/log grafana/promtail || true

echo "================================================="
echo " DEV NODE SETUP COMPLETE"
echo " Role: $NODE_ROLE"
echo " Log: $LOG"
echo "================================================="
