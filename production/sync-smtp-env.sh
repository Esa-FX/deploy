#!/usr/bin/env bash
# Sync SMTP credentials from Secrets Manager into crm-service .env file.
# Create secret esafx/{staging|production}/smtp JSON: host, port, user, password, from, ftd_notify_to, enabled
#
#   aws secretsmanager create-secret --name esafx/production/smtp --secret-string '{
#     "enabled": "true", "host": "smtp.gmail.com", "port": "587",
#     "user": "...", "password": "...", "from": "...", "ftd_notify_to": "..."
#   }'
#
# Usage: ./deploy/production/sync-smtp-env.sh
#        ENV_SUFFIX=staging SECRET_ID=esafx/staging/smtp ./deploy/staging/sync-smtp-env.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECRET_ID="${SECRET_ID:-esafx/production/smtp}"
REGION="${AWS_REGION:-ap-southeast-3}"
ENV_SUFFIX="${ENV_SUFFIX:-production}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi

CRM_ENV="$REPO_ROOT/crm-service/.env.${ENV_SUFFIX}"
if [[ ! -f "$CRM_ENV" ]]; then
  echo "Missing $CRM_ENV — copy from .env.${ENV_SUFFIX}.example first." >&2
  exit 1
fi

RAW="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text 2>/dev/null)" || {
  echo "Secret $SECRET_ID not found — set SMTP_* manually on $CRM_ENV (see crm-service/docs/ftd-email.md)" >&2
  exit 0
}

json_field() {
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$2',''))" <<<"$1"
}

ENABLED="$(json_field "$RAW" enabled)"
HOST="$(json_field "$RAW" host)"
PORT="$(json_field "$RAW" port)"
USER="$(json_field "$RAW" user)"
PASS="$(json_field "$RAW" password)"
FROM="$(json_field "$RAW" from)"
FTD_TO="$(json_field "$RAW" ftd_notify_to)"

compose_escape() {
  printf '%s' "$1" | sed 's/\$/$$/g'
}

set_env_var() {
  local file="$1" key="$2" value="$3"
  local escaped tmp
  escaped="$(compose_escape "$value")"
  tmp="$(mktemp)"
  grep -Ev "^\s*${key}\s*=" "$file" > "$tmp" || true
  { cat "$tmp"; echo "${key}=${escaped}"; } > "$file"
  rm -f "$tmp"
}

[[ -n "$ENABLED" ]] && set_env_var "$CRM_ENV" SMTP_ENABLED "$ENABLED"
[[ -n "$HOST" ]] && set_env_var "$CRM_ENV" SMTP_HOST "$HOST"
[[ -n "$PORT" ]] && set_env_var "$CRM_ENV" SMTP_PORT "$PORT"
[[ -n "$USER" ]] && set_env_var "$CRM_ENV" SMTP_USER "$USER"
[[ -n "$PASS" ]] && set_env_var "$CRM_ENV" SMTP_PASSWORD "$PASS"
[[ -n "$FROM" ]] && set_env_var "$CRM_ENV" SMTP_FROM "$FROM"
[[ -n "$FTD_TO" ]] && set_env_var "$CRM_ENV" FTD_NOTIFY_TO "$FTD_TO"

echo "Synced SMTP from $SECRET_ID into $CRM_ENV"
echo "Recreate: docker compose -f deploy/production/docker-compose.crm.yml up -d --force-recreate crm-api"
