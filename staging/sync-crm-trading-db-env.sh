#!/usr/bin/env bash
# Append TRADING_DB_* lines to crm-service/.env.staging from Secrets Manager.
# Run on app EC2: ./deploy/staging/sync-crm-trading-db-env.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/crm-service/.env.staging}"
SECRET_ID="${SECRET_ID:-esafx/staging/db/trading}"
REGION="${AWS_REGION:-ap-southeast-3}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — copy from .env.staging.example first." >&2
  exit 1
fi

RAW="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"
HOST="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['host'])")"
PORT="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['port'])")"
NAME="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['dbname'])")"
USER="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['username'])")"
PASS="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['password'])")"

TMP="$(mktemp)"
grep -Ev '^\s*TRADING_DB_(HOST|PORT|NAME|USER|PASSWORD|SSL|SSL_CA_FILE)\s*=' "$ENV_FILE" > "$TMP" || true
{
  cat "$TMP"
  echo "TRADING_DB_HOST=$HOST"
  echo "TRADING_DB_PORT=$PORT"
  echo "TRADING_DB_NAME=$NAME"
  echo "TRADING_DB_USER=$USER"
  echo "TRADING_DB_PASSWORD=$PASS"
  echo "TRADING_DB_SSL=true"
  echo "TRADING_DB_SSL_CA_FILE=/opt/esafx/global-bundle.pem"
} > "$ENV_FILE"
rm -f "$TMP"

echo "Updated TRADING_DB_* in $ENV_FILE from $SECRET_ID"
echo "Rebuild crm-api: docker compose -f deploy/staging/docker-compose.app.yml build crm-api"
