#!/usr/bin/env bash
# Deploy all app-tier services on staging EC2 (identity → crm migrate → pii-vault → crm-api → client).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/staging/docker-compose.app.yml}"

cd "$REPO_ROOT"

require_env() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "Missing $f — copy from .env.staging.example and fill values." >&2
    exit 1
  fi
}

for svc in identity-service crm-service pii-vault-service client-service; do
  require_env "$REPO_ROOT/$svc/.env.staging"
done

echo "==> identity migrations"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm identity-migrate

echo "==> crm migrations (includes pii_vault schema)"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm crm-migrate

echo "==> client migrations"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm client-migrate

echo "==> build & start"
docker compose -f "$COMPOSE_FILE" build identity pii-vault crm-api client
docker compose -f "$COMPOSE_FILE" up -d identity pii-vault crm-api client

echo "==> health"
curl -sf "http://127.0.0.1:8000/health" && echo " identity OK"
curl -sf "http://127.0.0.1:8004/health" && echo " pii-vault OK"
curl -sf "http://127.0.0.1:${CRM_PORT:-8001}/health" && echo " crm-api OK"
curl -sf "http://127.0.0.1:${CLIENT_PORT:-8002}/health" && echo " client OK"

echo "App tier deploy complete. Ensure MT_BRIDGE_SERVICE_URL points at mt EC2 before testing CRM finance."
