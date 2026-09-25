#!/usr/bin/env bash
# Sync inter-service tokens from esafx/production/service-tokens into .env.production files.
# Usage: ./deploy/production/sync-service-tokens-env.sh [--dry-run] [--rotate-crm-internal]
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"
if [[ ! -d "$REPO_ROOT/crm-service" && -d "$DEPLOY_ROOT/../crm-service" ]]; then
  REPO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"
elif [[ ! -d "$REPO_ROOT/crm-service" ]]; then
  REPO_ROOT="$DEPLOY_ROOT"
fi

# shellcheck source=scripts/service-tokens-sync-lib.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-lib.sh"

SECRET_ID="${SECRET_ID:-esafx/production/service-tokens}"
REGION="${AWS_REGION:-ap-southeast-3}"
ENV_SUFFIX="${ENV_SUFFIX:-production}"
DRY_RUN=false
ROTATE_CRM_INTERNAL=false

# TODO: confirm env var names in voip-gateway for CRM internal auth.
VOIP_CRM_TOKEN_ENV_KEY="${VOIP_CRM_TOKEN_ENV_KEY:-CRM_INTERNAL_TOKEN}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --rotate-crm-internal) ROTATE_CRM_INTERNAL=true ;;
    -h | --help)
      echo "Usage: $0 [--dry-run] [--rotate-crm-internal]" >&2
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
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

CRM_ENV="$REPO_ROOT/crm-service/.env.${ENV_SUFFIX}"
CLIENT_ENV="$REPO_ROOT/client-service/.env.${ENV_SUFFIX}"
PII_ENV="$REPO_ROOT/pii-vault-service/.env.${ENV_SUFFIX}"
VOIP_ENV="$REPO_ROOT/voip-gateway-service/.env.${ENV_SUFFIX}"

set_env_var "$CRM_ENV" CLIENT_SERVICE_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"
set_env_var "$CRM_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_CRM_TOKEN" "$DRY_RUN"
set_env_var "$CRM_ENV" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN" "$DRY_RUN"
set_env_var "$CRM_ENV" VOIP_GATEWAY_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"

set_env_var "$CLIENT_ENV" INTERNAL_SERVICE_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"
set_env_var "$CLIENT_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_CLIENT_TOKEN" "$DRY_RUN"

set_env_var "$PII_ENV" SERVICE_TOKEN "$PII_TOKEN" "$DRY_RUN"
set_env_var "$VOIP_ENV" INTERNAL_TOKEN "$CLIENT_TOKEN" "$DRY_RUN"

if [[ "$ROTATE_CRM_INTERNAL" == true ]]; then
  CRM_INTERNAL_TOKEN="$(require_key crm_internal)"
  set_env_var "$CRM_ENV" INTERNAL_SERVICE_TOKEN "$CRM_INTERNAL_TOKEN" "$DRY_RUN"
  set_env_var "$VOIP_ENV" "$VOIP_CRM_TOKEN_ENV_KEY" "$CRM_INTERNAL_TOKEN" "$DRY_RUN"
else
  echo "Skipping crm_internal (pass --rotate-crm-internal to set crm INTERNAL_SERVICE_TOKEN and voip CRM token)"
fi

echo "Synced service tokens from $SECRET_ID"
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] no files written"
  exit 0
fi
echo "Recreate CRM tier (low traffic; voip 401 window until voip host step):"
echo "  docker compose -f deploy/production/docker-compose.crm.yml up -d --no-deps --force-recreate crm-api client"
echo "Immediately on VoIP EC2:"
echo "  docker compose -f deploy/production/docker-compose.voip.yml up -d --no-deps --force-recreate voip-gateway"
