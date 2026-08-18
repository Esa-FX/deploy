#!/usr/bin/env bash
# Sync TRADING_DB_* into backoffice-service/.env.staging from Secrets Manager.
# Staging backoffice reads production trading (AccSum materialize lives on prod MT).
# Secret: esafx/production/db/trading-readonly (crm_trading_readonly — SELECT only).
# Writes password to /opt/esafx/secrets/trading_db_password_prod_readonly so Compose
# does not interpolate $ in env_file values.
# Run on app EC2: ./deploy/staging/sync-backoffice-trading-db-env.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/backoffice-service/.env.staging}"
SECRETS_DIR="${SECRETS_DIR:-/opt/esafx/secrets}"
PASSWORD_FILE="${SECRETS_DIR}/trading_db_password_prod_readonly"
SECRET_ID="${SECRET_ID:-esafx/production/db/trading-readonly}"
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

mkdir -p "$SECRETS_DIR"
umask 077
printf '%s' "$PASS" > "$PASSWORD_FILE"
chmod 644 "$PASSWORD_FILE"

TMP="$(mktemp)"
grep -Ev '^\s*TRADING_DB_(HOST|PORT|NAME|USER|PASSWORD|PASSWORD_FILE|SSL|SSL_CA_FILE)\s*=' "$ENV_FILE" > "$TMP" || true
{
  cat "$TMP"
  echo "TRADING_DB_HOST=$HOST"
  echo "TRADING_DB_PORT=$PORT"
  echo "TRADING_DB_NAME=$NAME"
  echo "TRADING_DB_USER=$USER"
  echo "TRADING_DB_PASSWORD_FILE=/run/secrets/trading_db_password_prod_readonly"
  echo "TRADING_DB_SSL=true"
  echo "TRADING_DB_SSL_CA_FILE=/opt/esafx/global-bundle.pem"
} > "$ENV_FILE"
rm -f "$TMP"

echo "Updated TRADING_DB_* in $ENV_FILE from $SECRET_ID"
echo "Wrote raw password to $PASSWORD_FILE (Compose-safe)"
echo "Rebuild backoffice: docker compose -f deploy/staging/docker-compose.app.yml build backoffice"
