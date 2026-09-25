#!/usr/bin/env bash
# Sync inter-service auth tokens from Secrets Manager into .env.staging files.
# Secret esafx/staging/service-tokens JSON keys: client, crm_internal, mt_bridge_*,
# pii_vault, legacy mt_bridge.
#
# crm-api CLIENT_SERVICE_TOKEN must match client-service INTERNAL_SERVICE_TOKEN (both = client).
# crm-api INTERNAL_SERVICE_TOKEN must match voip/whatsapp CRM_INTERNAL_TOKEN and client CRM_INTERNAL_TOKEN.
#
# Run on app EC2 after token rotation:
#   ./deploy/staging/sync-service-tokens-env.sh [--dry-run]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECRET_ID="${SECRET_ID:-esafx/staging/service-tokens}"
REGION="${AWS_REGION:-ap-southeast-3}"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h | --help)
      echo "Usage: $0 [--dry-run]" >&2
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
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required" >&2
  exit 1
fi

RAW="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"

require_key() {
  local key="$1"
  python3 - "$key" <<'PY' <<<"$RAW"
import json, sys
key = sys.argv[1]
data = json.load(sys.stdin)
if key not in data or not str(data[key]).strip():
    sys.exit(f"Secret {key!r} is missing or empty in {SECRET_ID:-service-tokens}")
val = str(data[key])
if val == "dev-internal-token":
    sys.exit(f"Secret {key!r} is the placeholder dev-internal-token; set a real value in Secrets Manager")
print(val)
PY
}

CLIENT_TOKEN="$(require_key client)"
CRM_INTERNAL_TOKEN="$(require_key crm_internal)"
MT_CRM_TOKEN="$(require_key mt_bridge_crm)"
MT_CLIENT_TOKEN="$(require_key mt_bridge_client)"
PII_TOKEN="$(require_key pii_vault)"

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
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] would set $key in $file"
    return 0
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
WA_ENV="$REPO_ROOT/whatsapp-gateway-service/.env.staging"

set_env_var "$CRM_ENV" CLIENT_SERVICE_TOKEN "$CLIENT_TOKEN"
set_env_var "$CRM_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_CRM_TOKEN"
set_env_var "$CRM_ENV" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN"
set_env_var "$CRM_ENV" VOIP_GATEWAY_TOKEN "$CLIENT_TOKEN"
set_env_var "$CRM_ENV" WHATSAPP_GATEWAY_TOKEN "$CLIENT_TOKEN"
set_env_var "$CRM_ENV" INTERNAL_SERVICE_TOKEN "$CRM_INTERNAL_TOKEN"

set_env_var "$CLIENT_ENV" INTERNAL_SERVICE_TOKEN "$CLIENT_TOKEN"
set_env_var "$CLIENT_ENV" MT_BRIDGE_SERVICE_TOKEN "$MT_CLIENT_TOKEN"
set_env_var "$CLIENT_ENV" CRM_INTERNAL_TOKEN "$CRM_INTERNAL_TOKEN"

set_env_var "$PII_ENV" SERVICE_TOKEN "$PII_TOKEN"
set_env_var "$VOIP_ENV" INTERNAL_TOKEN "$CLIENT_TOKEN"
set_env_var "$VOIP_ENV" CRM_INTERNAL_TOKEN "$CRM_INTERNAL_TOKEN"
set_env_var "$WA_ENV" INTERNAL_TOKEN "$CLIENT_TOKEN"
set_env_var "$WA_ENV" CRM_INTERNAL_TOKEN "$CRM_INTERNAL_TOKEN"
set_env_var "$WA_ENV" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN"

echo "Synced service tokens from $SECRET_ID into:"
echo "  - crm-service: CLIENT_SERVICE_TOKEN, MT_BRIDGE_SERVICE_TOKEN, INTERNAL_SERVICE_TOKEN, ..."
echo "  - client-service: INTERNAL_SERVICE_TOKEN, MT_BRIDGE_SERVICE_TOKEN, CRM_INTERNAL_TOKEN"
echo "  - voip-gateway-service: INTERNAL_TOKEN, CRM_INTERNAL_TOKEN"
echo "  - whatsapp-gateway-service: INTERNAL_TOKEN, CRM_INTERNAL_TOKEN"
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] no files written"
  exit 0
fi
echo "Recreate callers together (avoid 401 window):"
echo "  docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --force-recreate crm-api client voip-gateway"
