#!/usr/bin/env bash
# Sync inter-service tokens from esafx/production/service-tokens into .env.production files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECRET_ID="${SECRET_ID:-esafx/production/service-tokens}"
REGION="${AWS_REGION:-ap-southeast-3}"
ENV_SUFFIX="${ENV_SUFFIX:-production}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi

RAW="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"
CLIENT_TOKEN="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['client'])")"
MT_TOKEN="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['mt_bridge'])")"
PII_TOKEN="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['pii_vault'])")"

compose_escape() {
  printf '%s' "$1" | sed 's/\$/$$/g'
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  [[ -f "$file" ]] || { echo "Skip $key — missing $file"; return 0; }
  local escaped tmp
  escaped="$(compose_escape "$value")"
  tmp="$(mktemp)"
  grep -Ev "^\s*${key}\s*=" "$file" > "$tmp" || true
  { cat "$tmp"; echo "${key}=${escaped}"; } > "$file"
  rm -f "$tmp"
}

CRM_ENV="$REPO_ROOT/crm-service/.env.${ENV_SUFFIX}"
CLIENT_ENV="$REPO_ROOT/client-service/.env.${ENV_SUFFIX}"
PII_ENV="$REPO_ROOT/pii-vault-service/.env.${ENV_SUFFIX}"

set_env_var "$CRM_ENV" CLIENT_SERVICE_TOKEN "$CLIENT_TOKEN"
set_env_var "$CRM_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_TOKEN"
set_env_var "$CRM_ENV" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN"
set_env_var "$CLIENT_ENV" INTERNAL_SERVICE_TOKEN "$CLIENT_TOKEN"
set_env_var "$CLIENT_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_TOKEN"
set_env_var "$PII_ENV" SERVICE_TOKEN "$PII_TOKEN"

echo "Synced service tokens from $SECRET_ID"
