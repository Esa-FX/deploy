#!/usr/bin/env bash
# Deploy all app-tier services on staging EC2 (identity → crm migrate → pii-vault → crm-api → client).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/staging/docker-compose.app.yml}"

cd "$REPO_ROOT"

CA_BUNDLE="${RDS_CA_BUNDLE:-/opt/esafx/global-bundle.pem}"
if [[ ! -f "$CA_BUNDLE" ]]; then
  echo "==> Download RDS CA bundle to $CA_BUNDLE"
  sudo mkdir -p "$(dirname "$CA_BUNDLE")"
  sudo curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o "$CA_BUNDLE"
  sudo chmod 644 "$CA_BUNDLE"
fi

require_env() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "Missing $f — copy from .env.staging.example and fill values." >&2
    exit 1
  fi
}

for svc in identity-service crm-service pii-vault-service client-service audit-log-service; do
  require_env "$REPO_ROOT/$svc/.env.staging"
done

echo "==> identity migrations (rebuild image so env.py / migrations are current)"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build identity-migrate

echo "==> crm migrations (includes pii_vault schema)"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build crm-migrate

echo "==> client migrations"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build client-migrate

echo "==> audit-log migrations"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build audit-migrate

echo "==> build & start"
docker compose -f "$COMPOSE_FILE" build identity pii-vault audit-log crm-api client
docker compose -f "$COMPOSE_FILE" up -d identity pii-vault audit-log crm-api client

echo "==> health"
curl -sf "http://127.0.0.1:8000/health" && echo " identity OK"
curl -sf "http://127.0.0.1:8004/health" && echo " pii-vault OK"
curl -sf "http://127.0.0.1:8005/health" && echo " audit-log OK"
curl -sf "http://127.0.0.1:${CRM_PORT:-8001}/health" && echo " crm-api OK"
curl -sf "http://127.0.0.1:${CLIENT_PORT:-8002}/health" && echo " client OK"

echo "App tier deploy complete. Ensure MT_BRIDGE_SERVICE_URL points at mt EC2 before testing CRM finance."
