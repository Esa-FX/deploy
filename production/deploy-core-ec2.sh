#!/usr/bin/env bash
# Deploy core tier on production core EC2 (identity, pii-vault, audit-log).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/production/docker-compose.core.yml}"

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
    echo "Missing $f — copy from .env.staging.example → .env.production and fill terraform outputs." >&2
    exit 1
  fi
}

for svc in identity-service pii-vault-service audit-log-service crm-service; do
  require_env "$REPO_ROOT/$svc/.env.production"
done

echo "==> migrations (core DB schemas)"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build identity-migrate
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build crm-migrate
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build audit-migrate

echo "==> sync production secrets"
"$REPO_ROOT/deploy/production/sync-service-tokens-env.sh"

echo "==> build & start core tier"
docker compose -f "$COMPOSE_FILE" build identity pii-vault audit-log
docker compose -f "$COMPOSE_FILE" up -d identity pii-vault audit-log

echo "==> health"
curl -sf "http://127.0.0.1:8000/health" && echo " identity OK"
curl -sf "http://127.0.0.1:8004/health" && echo " pii-vault OK"
curl -sf "http://127.0.0.1:8005/health" && echo " audit-log OK"

echo "Core tier deploy complete."
