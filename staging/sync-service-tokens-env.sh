#!/usr/bin/env bash
# Sync inter-service auth tokens from Secrets Manager into .env.staging files.
# Secret esafx/staging/service-tokens JSON keys: client, mt_bridge, pii_vault
#
# crm-api CLIENT_SERVICE_TOKEN must match client-service INTERNAL_SERVICE_TOKEN (both = client).
# Run on app EC2 after terraform apply or token rotation:
#   ./deploy/staging/sync-service-tokens-env.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECRET_ID="${SECRET_ID:-esafx/staging/service-tokens}"
REGION="${AWS_REGION:-ap-southeast-3}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required" >&2
  exit 1
fi

RAW="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"
CLIENT_TOKEN="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['client'])")"
MT_TOKEN="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['mt_bridge'])")"
PII_TOKEN="$(echo "$RAW" | python3 -c "import json,sys; print(json.load(sys.stdin)['pii_vault'])")"

# Docker Compose interpolates $ in env_file — escape each $ as $$.
compose_escape() {
  printf '%s' "$1" | sed 's/\$/$$/g'
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  if [[ ! -f "$file" ]]; then
    echo "Missing $file — copy from .env.staging.example first." >&2
    exit 1
  fi
  local escaped
  escaped="$(compose_escape "$value")"
  local tmp
  tmp="$(mktemp)"
  grep -Ev "^\s*${key}\s*=" "$file" > "$tmp" || true
  {
    cat "$tmp"
    echo "${key}=${escaped}"
  } > "$file"
  rm -f "$tmp"
}

CRM_ENV="$REPO_ROOT/crm-service/.env.staging"
CLIENT_ENV="$REPO_ROOT/client-service/.env.staging"
PII_ENV="$REPO_ROOT/pii-vault-service/.env.staging"
VOIP_ENV="$REPO_ROOT/voip-gateway-service/.env.staging"

set_env_var "$CRM_ENV" CLIENT_SERVICE_TOKEN "$CLIENT_TOKEN"
set_env_var "$CRM_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_TOKEN"
set_env_var "$CRM_ENV" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN"
set_env_var "$CRM_ENV" VOIP_GATEWAY_TOKEN "$CLIENT_TOKEN"
set_env_var "$CRM_ENV" INTERNAL_SERVICE_TOKEN "$CLIENT_TOKEN"

set_env_var "$CLIENT_ENV" INTERNAL_SERVICE_TOKEN "$CLIENT_TOKEN"
set_env_var "$CLIENT_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_TOKEN"

set_env_var "$PII_ENV" SERVICE_TOKEN "$PII_TOKEN"
set_env_var "$VOIP_ENV" INTERNAL_TOKEN "$CLIENT_TOKEN"
set_env_var "$VOIP_ENV" CRM_INTERNAL_TOKEN "$CLIENT_TOKEN"

echo "Synced service tokens from $SECRET_ID into:"
echo "  - crm-service: CLIENT_SERVICE_TOKEN, MT_BRIDGE_SERVICE_TOKEN, PII_VAULT_SERVICE_TOKEN, VOIP_GATEWAY_TOKEN, INTERNAL_SERVICE_TOKEN"
echo "  - client-service: INTERNAL_SERVICE_TOKEN, MT_BRIDGE_SERVICE_TOKEN"
echo "  - pii-vault-service: SERVICE_TOKEN"
echo "  - voip-gateway-service: INTERNAL_TOKEN, CRM_INTERNAL_TOKEN"
echo "Recreate affected containers:"
echo "  docker compose -f deploy/staging/docker-compose.app.yml up -d --force-recreate crm-api client pii-vault voip-gateway"
