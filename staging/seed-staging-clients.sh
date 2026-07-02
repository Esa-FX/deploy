#!/usr/bin/env bash
# Seed demo clients + trading data on staging app EC2.
# Uses master trading DB creds (write) for seeding, then restores readonly for crm-api.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/deploy/staging/docker-compose.app.yml"
MASTER_SECRET_ID="${MASTER_SECRET_ID:-esafx/staging/db/trading}"
REGION="${AWS_REGION:-ap-southeast-3}"

cd "$REPO_ROOT"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi

SEED_SCRIPT="$REPO_ROOT/crm-service/scripts/seed_clients.py"
if [[ ! -f "$SEED_SCRIPT" ]]; then
  echo "Missing $SEED_SCRIPT — git pull crm-service on staging first." >&2
  exit 1
fi

SECRETS_DIR="${SECRETS_DIR:-/opt/esafx/secrets}"
MASTER_PASSWORD_FILE="${SECRETS_DIR}/trading_master_password"
CONTAINER_MASTER_PASSWORD_FILE="/run/secrets/trading_master_password"

echo "==> Load master trading DB credentials from $MASTER_SECRET_ID"
RAW="$(aws secretsmanager get-secret-value --secret-id "$MASTER_SECRET_ID" --region "$REGION" --query SecretString --output text)"
export TRADING_DB_HOST="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['host'])")"
export TRADING_DB_PORT="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['port'])")"
export TRADING_DB_NAME="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['dbname'])")"
export TRADING_DB_USER="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['username'])")"
MASTER_PASS="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['password'])")"
export TRADING_DB_SSL=true
export TRADING_DB_SSL_CA_FILE="${TRADING_DB_SSL_CA_FILE:-/opt/esafx/global-bundle.pem}"

# Compose interpolates $ in -e values; write password to a world-readable file for the container user.
mkdir -p "$SECRETS_DIR"
umask 077
printf '%s' "$MASTER_PASS" > "$MASTER_PASSWORD_FILE"
chmod 644 "$MASTER_PASSWORD_FILE"

echo "==> Rebuild crm-api (includes scripts/seed_clients.py + httpx)"
docker compose -f "$COMPOSE_FILE" build crm-api

echo "==> Seed clients (core + esafx_trading; --reset removes prior seed-client rows)"
# EC2 may lag crm-service git; pass master password via env (old seed_clients.py ignores PASSWORD_FILE).
docker compose -f "$COMPOSE_FILE" run --rm --no-deps \
  -e TRADING_DB_HOST \
  -e TRADING_DB_PORT \
  -e TRADING_DB_NAME \
  -e TRADING_DB_USER \
  -e TRADING_DB_SSL \
  -e TRADING_DB_SSL_CA_FILE \
  -e TRADING_DB_PASSWORD_FILE= \
  -v "$MASTER_PASSWORD_FILE:${CONTAINER_MASTER_PASSWORD_FILE}:ro" \
  -v /opt/esafx/global-bundle.pem:/opt/esafx/global-bundle.pem:ro \
  crm-api bash -lc "export TRADING_DB_PASSWORD=\$(cat ${CONTAINER_MASTER_PASSWORD_FILE}); exec /opt/venv/bin/python scripts/seed_clients.py --reset --skip-pii \"\$@\"" -- "$@"

echo "==> Restore readonly trading creds for crm-api runtime"
"$REPO_ROOT/deploy/staging/sync-crm-trading-db-env.sh"
docker compose -f "$COMPOSE_FILE" up -d --force-recreate crm-api

echo "==> Trading DB diagnostics"
"$REPO_ROOT/deploy/staging/diag-trading-db.sh" || true

echo "Done. Check KPI report and fund transactions for the current month."
