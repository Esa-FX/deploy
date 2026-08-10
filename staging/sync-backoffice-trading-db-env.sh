#!/usr/bin/env bash
# Sync TRADING_DB_* into backoffice-service/.env.staging from prod trading readonly.
# Staging backoffice reads production fleet/AccSum data; CRM stays on staging trading DB.
# Uses esafx/production/db/trading-readonly (crm_trading_readonly — SELECT only).
# Password file is separate from CRM staging so sync-crm-trading-db-env.sh is unaffected.
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
  if [[ -f "$REPO_ROOT/backoffice-service/.env.staging.example" ]]; then
    cp "$REPO_ROOT/backoffice-service/.env.staging.example" "$ENV_FILE"
  else
    echo "Missing $ENV_FILE — copy from .env.staging.example first." >&2
    exit 1
  fi
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
