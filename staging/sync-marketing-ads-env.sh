#!/usr/bin/env bash
# Sync marketing ads OAuth/Fernet settings from Secrets Manager into crm-service/.env.staging
#
# Secret JSON (esafx/staging/marketing-ads):
#   fernet_key, google_client_id, google_client_secret, google_redirect_uri,
#   google_developer_token, return_url
#
# Usage: ./deploy/staging/sync-marketing-ads-env.sh [--dry-run]
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$DEPLOY_ROOT/.." && pwd)"
# shellcheck source=scripts/service-tokens-sync-lib.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-lib.sh"

SECRET_ID="${SECRET_ID:-esafx/staging/marketing-ads}"
REGION="${AWS_REGION:-ap-southeast-3}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    -h | --help)
      echo "Usage: $0 [--dry-run]" >&2
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
  shift
done

CRM_ENV="${REPO_ROOT}/crm-service/.env.staging"
if [[ ! -f "$CRM_ENV" ]]; then
  echo "Missing $CRM_ENV" >&2
  exit 1
fi

RAW="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"

apply_key() {
  local json_key="$1"
  local env_key="$2"
  local value
  value="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2],''))" "$RAW" "$json_key")"
  if [[ -z "$value" ]]; then
    echo "Missing key $json_key in $SECRET_ID" >&2
    exit 1
  fi
  set_env_var "$CRM_ENV" "$env_key" "$value" "$DRY_RUN"
}

apply_key fernet_key MARKETING_ADS_FERNET_KEY
apply_key google_client_id MARKETING_GOOGLE_ADS_CLIENT_ID
apply_key google_client_secret MARKETING_GOOGLE_ADS_CLIENT_SECRET
apply_key google_redirect_uri MARKETING_GOOGLE_ADS_REDIRECT_URI
apply_key google_developer_token MARKETING_GOOGLE_ADS_DEVELOPER_TOKEN
apply_key return_url MARKETING_ADS_RETURN_URL

echo "Synced marketing ads env from $SECRET_ID"
if [[ "$DRY_RUN" != true ]]; then
  echo "Recreate crm-api: docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api"
fi
