#!/usr/bin/env bash
# Sync inter-service auth tokens from Secrets Manager into .env.staging files.
#
# crm-api CLIENT_SERVICE_TOKEN must match client-service INTERNAL_SERVICE_TOKEN (both = client key).
# client-service does not call crm; do not set CRM-facing tokens on client-service here.
#
# crm_internal rotation (crm INTERNAL_SERVICE_TOKEN + voip/whatsapp → crm) requires --rotate-crm-internal.
#
# Usage: ./deploy/staging/sync-service-tokens-env.sh [--dry-run] [--rotate-crm-internal]
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"
# Monorepo layout: services live next to deploy/. Deploy-only checkout: use DEPLOY_ROOT parent once.
if [[ ! -d "$REPO_ROOT/crm-service" && -d "$DEPLOY_ROOT/../crm-service" ]]; then
  REPO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"
elif [[ ! -d "$REPO_ROOT/crm-service" ]]; then
  REPO_ROOT="$DEPLOY_ROOT"
fi

# shellcheck source=scripts/service-tokens-sync-lib.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-lib.sh"

SECRET_ID="${SECRET_ID:-esafx/staging/service-tokens}"
REGION="${AWS_REGION:-ap-southeast-3}"
DRY_RUN=false
ROTATE_CRM_INTERNAL=false

# TODO: confirm env var names in voip-gateway / whatsapp-gateway for CRM internal auth.
VOIP_CRM_TOKEN_ENV_KEY="${VOIP_CRM_TOKEN_ENV_KEY:-CRM_INTERNAL_TOKEN}"
WHATSAPP_CRM_TOKEN_ENV_KEY="${WHATSAPP_CRM_TOKEN_ENV_KEY:-CRM_INTERNAL_TOKEN}"

usage() {
  echo "Usage: $0 [--dry-run] [--rotate-crm-internal]" >&2
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --rotate-crm-internal) ROTATE_CRM_INTERNAL=true ;;
    -h | --help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 2 ;;
  esac
  shift
done

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required" >&2
  exit 1
fi

RAW="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"

require_key() {
  require_service_token_key "$1" "$SECRET_ID" "$RAW"
}

CLIENT_TOKEN="$(require_key client)"
MT_CRM_TOKEN="$(require_key mt_bridge_crm)"
MT_CLIENT_TOKEN="$(require_key mt_bridge_client)"
PII_TOKEN="$(require_key pii_vault)"

CRM_ENV="$REPO_ROOT/crm-service/.env.staging"
CLIENT_ENV="$REPO_ROOT/client-service/.env.staging"
PII_ENV="$REPO_ROOT/pii-vault-service/.env.staging"
VOIP_ENV="$REPO_ROOT/voip-gateway-service/.env.staging"
WA_ENV="$REPO_ROOT/whatsapp-gateway-service/.env.staging"

set_env_var "$CRM_ENV" CLIENT_SERVICE_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"
set_env_var "$CRM_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_CRM_TOKEN" "$DRY_RUN"
set_env_var "$CRM_ENV" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN" "$DRY_RUN"
set_env_var "$CRM_ENV" VOIP_GATEWAY_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"
set_env_var "$CRM_ENV" WHATSAPP_GATEWAY_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"

set_env_var "$CLIENT_ENV" INTERNAL_SERVICE_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"
set_env_var "$CLIENT_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_CLIENT_TOKEN" "$DRY_RUN"

set_env_var "$PII_ENV" SERVICE_TOKEN "$PII_TOKEN" "$DRY_RUN"
set_env_var "$VOIP_ENV" INTERNAL_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"
set_env_var "$WA_ENV" INTERNAL_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"
set_env_var "$WA_ENV" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN" "$DRY_RUN"

if [[ "$ROTATE_CRM_INTERNAL" == true ]]; then
  CRM_INTERNAL_TOKEN="$(require_key crm_internal)"
  set_env_var "$CRM_ENV" INTERNAL_SERVICE_TOKEN "$CRM_INTERNAL_TOKEN" "$DRY_RUN"
  set_env_var "$VOIP_ENV" "$VOIP_CRM_TOKEN_ENV_KEY" "$CRM_INTERNAL_TOKEN" "$DRY_RUN"
  set_env_var "$WA_ENV" "$WHATSAPP_CRM_TOKEN_ENV_KEY" "$CRM_INTERNAL_TOKEN" "$DRY_RUN"
else
  echo "Skipping crm_internal (pass --rotate-crm-internal to set crm INTERNAL_SERVICE_TOKEN and voip/whatsapp CRM tokens)"
fi

echo "Synced service tokens from $SECRET_ID"
echo "  - crm-service: CLIENT_SERVICE_TOKEN, MT_BRIDGE_SERVICE_TOKEN, ..."
echo "  - client-service: INTERNAL_SERVICE_TOKEN, MT_BRIDGE_SERVICE_TOKEN"
echo "  - voip/whatsapp: INTERNAL_TOKEN (+ CRM token when --rotate-crm-internal)"
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] no files written"
  exit 0
fi
echo "Recreate callers together (avoid 401 window):"
echo "  docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api client voip-gateway"
