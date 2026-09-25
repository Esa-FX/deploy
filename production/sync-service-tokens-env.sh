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
# shellcheck source=scripts/service-tokens-sync-apply.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-apply.sh"

SECRET_ID="${SECRET_ID:-esafx/production/service-tokens}"
REGION="${AWS_REGION:-ap-southeast-3}"
ENV_SUFFIX="${ENV_SUFFIX:-production}"
DRY_RUN=false
ROTATE_CRM_INTERNAL=false

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

service_tokens_sync_apply "$SECRET_ID" "$RAW" "$REPO_ROOT" "$ENV_SUFFIX" "$DRY_RUN" "$ROTATE_CRM_INTERNAL" false

echo "Synced service tokens from $SECRET_ID"
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] no files written"
  exit 0
fi
if [[ "$ROTATE_CRM_INTERNAL" == true ]]; then
  echo "Production: crm and voip are on different hosts — short voip→crm 401 window between steps. Use low traffic."
  echo "  CRM EC2: docker compose -f deploy/production/docker-compose.crm.yml up -d --no-deps --force-recreate crm-api"
  echo "  VoIP EC2 (immediately after): docker compose -f deploy/production/docker-compose.voip.yml up -d --no-deps --force-recreate voip-gateway"
else
  echo "  docker compose -f deploy/production/docker-compose.crm.yml up -d --no-deps --force-recreate crm-api client"
fi
