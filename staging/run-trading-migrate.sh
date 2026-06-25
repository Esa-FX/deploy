#!/usr/bin/env bash
# Run mt-bridge Alembic migrations (including crm_trading_readonly role).
# Uses master trading DB creds + CRM_TRADING_READONLY_PASSWORD from Secrets Manager.
#
# Run from repo root on app EC2 or a workstation with VPC/RDS access:
#   ./deploy/staging/run-trading-migrate.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVICE_ROOT="${SERVICE_ROOT:-$REPO_ROOT/mt-bridge-service}"
MASTER_SECRET_ID="${MASTER_SECRET_ID:-esafx/staging/db/trading}"
READONLY_SECRET_ID="${READONLY_SECRET_ID:-esafx/staging/db/trading-readonly}"
REGION="${AWS_REGION:-ap-southeast-3}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi

MASTER_RAW="$(aws secretsmanager get-secret-value --secret-id "$MASTER_SECRET_ID" --region "$REGION" --query SecretString --output text)"
READONLY_RAW="$(aws secretsmanager get-secret-value --secret-id "$READONLY_SECRET_ID" --region "$REGION" --query SecretString --output text)"

export TRADING_DB_HOST="$(echo "$MASTER_RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['host'])")"
export TRADING_DB_PORT="$(echo "$MASTER_RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['port'])")"
export TRADING_DB_NAME="$(echo "$MASTER_RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['dbname'])")"
export TRADING_DB_USER="$(echo "$MASTER_RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['username'])")"
export TRADING_DB_PASSWORD="$(echo "$MASTER_RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['password'])")"
export TRADING_DB_SSL=true
export TRADING_DB_SSL_CA_FILE="${TRADING_DB_SSL_CA_FILE:-/opt/esafx/global-bundle.pem}"
export CRM_TRADING_READONLY_PASSWORD="$(echo "$READONLY_RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['password'])")"
export APP_ENV=staging

PYTHON="${SERVICE_ROOT}/.venv/Scripts/python.exe"
if [[ ! -x "$PYTHON" ]]; then
  PYTHON="${SERVICE_ROOT}/.venv/bin/python"
fi
if [[ ! -x "$PYTHON" ]]; then
  PYTHON="python3"
fi

cd "$SERVICE_ROOT"
"$PYTHON" -m alembic upgrade head
"$PYTHON" scripts/sync_crm_readonly_role.py
echo "Trading DB migrations complete."
