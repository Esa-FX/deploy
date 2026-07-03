#!/usr/bin/env bash
# Deploy CRM tier on production crm EC2 (crm-api + client-service).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/production/docker-compose.crm.yml}"

cd "$REPO_ROOT"

CA_BUNDLE="${RDS_CA_BUNDLE:-/opt/esafx/global-bundle.pem}"
if [[ ! -f "$CA_BUNDLE" ]]; then
  sudo mkdir -p "$(dirname "$CA_BUNDLE")"
  sudo curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o "$CA_BUNDLE"
  sudo chmod 644 "$CA_BUNDLE"
fi

require_env() {
  [[ -f "$1" ]] || { echo "Missing $1" >&2; exit 1; }
}

for svc in crm-service client-service; do
  require_env "$REPO_ROOT/$svc/.env.production"
done

echo "==> client migrations"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build client-migrate

echo "==> sync tokens + trading DB env"
"$REPO_ROOT/deploy/production/sync-service-tokens-env.sh"
"$REPO_ROOT/deploy/production/sync-crm-trading-db-env.sh"
"$REPO_ROOT/deploy/production/sync-smtp-env.sh" || true

echo "==> build & start CRM tier"
docker compose -f "$COMPOSE_FILE" build crm-api client
docker compose -f "$COMPOSE_FILE" up -d crm-api client

curl -sf "http://127.0.0.1:8001/health" && echo " crm-api OK"
curl -sf "http://127.0.0.1:8002/health" && echo " client OK"

echo "CRM tier deploy complete."
