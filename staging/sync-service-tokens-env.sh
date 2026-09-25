#!/usr/bin/env bash
# Sync inter-service auth tokens from Secrets Manager into .env.staging files.
#
# Pairing (client key): crm CLIENT_SERVICE_TOKEN == client INTERNAL_SERVICE_TOKEN.
# Gateway pairs (crm VOIP_GATEWAY_TOKEN == voip INTERNAL_TOKEN, etc.) are keep-existing on both sides in normal sync.
#
# --rotate-crm-internal: writes only crm INTERNAL_SERVICE_TOKEN and gateway CRM_INTERNAL_TOKEN
# (voip + whatsapp on staging) from crm_internal. Does not touch pairing keys.
#
# Usage: ./deploy/staging/sync-service-tokens-env.sh [--dry-run] [--rotate-crm-internal]
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
# shellcheck source=scripts/service-tokens-sync-apply.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-apply.sh"

SECRET_ID="${SECRET_ID:-esafx/staging/service-tokens}"
REGION="${AWS_REGION:-ap-southeast-3}"
DRY_RUN=false
ROTATE_CRM_INTERNAL=false

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

service_tokens_sync_apply "$SECRET_ID" "$RAW" "$REPO_ROOT" staging "$DRY_RUN" "$ROTATE_CRM_INTERNAL" true

echo "Synced service tokens from $SECRET_ID"
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] no files written"
  exit 0
fi
if [[ "$ROTATE_CRM_INTERNAL" == true ]]; then
  echo "Recreate crm + gateways together (avoid crm_internal 401 window):"
  echo "  docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api voip-gateway whatsapp-gateway"
else
  echo "After mt_bridge token changes, recreate crm-api and client:"
  echo "  docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api client"
fi
