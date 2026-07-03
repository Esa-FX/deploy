#!/usr/bin/env bash
# Bootstrap production Linux EC2: clone repos, write .env.production from Secrets Manager, deploy tier.
# Usage: TIER=core|crm|voip ./deploy/production/bootstrap-linux-ec2.sh
set -euo pipefail

TIER="${TIER:?Set TIER=core|crm|voip}"
ROOT="${ESAFX_ROOT:-/opt/esafx}"
REGION="${AWS_REGION:-ap-southeast-3}"
BRANCH="${ESAFX_BRANCH:-main}"

# Terraform outputs (production)
CORE_IP="${CORE_IP:-10.1.133.252}"
CRM_IP="${CRM_IP:-10.1.134.250}"
VOIP_IP="${VOIP_IP:-10.1.12.152}"
MT_IP="${MT_IP:-10.1.143.205}"
COGNITO_POOL="${COGNITO_POOL:-ap-southeast-3_Oxz4wxhRL}"
COGNITO_CLIENT="${COGNITO_CLIENT:-5pm21ljg6citjs6bjjigjvki4a}"
REDIS_HOST="${REDIS_HOST:-esafx-production-redis.jwmnjk.0001.apse3.cache.amazonaws.com}"
AUDIT_BUS="${AUDIT_BUS:-esafx-production-audit}"
AUDIT_SQS="${AUDIT_SQS:-https://sqs.ap-southeast-3.amazonaws.com/612524168745/esafx-production-audit-ingest}"
KMS_ARN="${KMS_ARN:-arn:aws:kms:ap-southeast-3:612524168745:key/62373d21-baed-4c12-a83c-f4e68e9d0697}"
CALL_BUCKET="${CALL_BUCKET:-esafx-production-call-recordings-612524168745}"
FTD_BUCKET="${FTD_BUCKET:-esafx-production-ftd-uploads-612524168745}"
ACCOUNT_ID="${ACCOUNT_ID:-612524168745}"

declare -A TIER_REPOS=(
  [core]="deploy identity-service pii-vault-service audit-log-service crm-service"
  [crm]="deploy crm-service client-service"
  [voip]="deploy voip-gateway-service"
)

repos="${TIER_REPOS[$TIER]:-}"
if [[ -z "$repos" ]]; then
  echo "Unknown TIER=$TIER" >&2
  exit 1
fi

sudo mkdir -p "$ROOT/secrets"
sudo chown -R "$(whoami):$(whoami)" "$ROOT" 2>/dev/null || true
cd "$ROOT"

if [[ ! -f "$ROOT/global-bundle.pem" ]]; then
  curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o "$ROOT/global-bundle.pem"
fi

clone_repo() {
  local name="$1"
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    GITHUB_TOKEN="$(aws secretsmanager get-secret-value --secret-id esafx/production/github-clone --region "$REGION" --query SecretString --output text 2>/dev/null || true)"
  fi
  local url="https://github.com/Esa-FX/${name}.git"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    url="https://x-access-token:${GITHUB_TOKEN}@github.com/Esa-FX/${name}.git"
  fi
  if [[ -d "$name/.git" ]]; then
    git -C "$name" remote set-url origin "$url"
    git -C "$name" fetch origin "$BRANCH"
    git -C "$name" checkout "$BRANCH"
    git -C "$name" pull origin "$BRANCH"
    git -C "$name" remote set-url origin "https://github.com/Esa-FX/${name}.git"
  else
    git clone --branch "$BRANCH" --depth 1 "$url" "$name"
    git -C "$name" remote set-url origin "https://github.com/Esa-FX/${name}.git"
  fi
}

for r in $repos; do
  echo "==> clone/pull $r"
  clone_repo "$r"
done

json_field() {
  python3 -c "import json,sys; print(json.load(sys.stdin)['$2'])" <<<"$1"
}

CORE_JSON="$(aws secretsmanager get-secret-value --secret-id esafx/production/db/core --region "$REGION" --query SecretString --output text)"
CORE_PASS="$(json_field "$CORE_JSON" password)"
CORE_HOST="$(json_field "$CORE_JSON" host)"
CORE_DB="$(json_field "$CORE_JSON" dbname)"
TOKENS_JSON="$(aws secretsmanager get-secret-value --secret-id esafx/production/service-tokens --region "$REGION" --query SecretString --output text)"
CLIENT_TOKEN="$(json_field "$TOKENS_JSON" client)"
MT_TOKEN="$(json_field "$TOKENS_JSON" mt_bridge)"
PII_TOKEN="$(json_field "$TOKENS_JSON" pii_vault)"
AUDIT_KEY="$(aws secretsmanager get-secret-value --secret-id esafx/production/audit/api-key --region "$REGION" --query SecretString --output text)"

write_env() {
  local file="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    cp "$file" "$tmp"
  elif [[ -f "${file%.production}.staging.example" ]]; then
    cp "${file%.production}.staging.example" "$tmp"
  elif [[ -f "${file%.production}.example" ]]; then
    cp "${file%.production}.example" "$tmp"
  else
    touch "$tmp"
  fi
  while [[ $# -ge 2 ]]; do
    local key="$1" val="$2"
    shift 2
    grep -Ev "^\s*${key}\s*=" "$tmp" > "${tmp}.new" || true
    mv "${tmp}.new" "$tmp"
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
  done
  mv "$tmp" "$file"
}

PII_ENV="$ROOT/pii-vault-service/.env.production"
if [[ "$TIER" == "core" ]]; then
  if [[ ! -f "$PII_ENV" ]] || ! grep -q '^PII_ENCRYPTION_KEY=.' "$PII_ENV" 2>/dev/null; then
    PII_FERNET="$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" 2>/dev/null || openssl rand -base64 32)"
    PII_PHONE="$(openssl rand -hex 16)"
    PII_EMAIL="$(openssl rand -hex 16)"
  else
    PII_FERNET="$(grep '^PII_ENCRYPTION_KEY=' "$PII_ENV" | cut -d= -f2-)"
    PII_PHONE="$(grep '^PII_HMAC_KEY_PHONE=' "$PII_ENV" | cut -d= -f2-)"
    PII_EMAIL="$(grep '^PII_HMAC_KEY_EMAIL=' "$PII_ENV" | cut -d= -f2-)"
  fi
  write_env "$PII_ENV" \
    DB_HOST "$CORE_HOST" DB_PORT 5432 DB_NAME "$CORE_DB" DB_USER dbadmin DB_PASSWORD "$CORE_PASS" \
    DB_SSL true DB_SSL_CA_FILE "$ROOT/global-bundle.pem" \
    SERVICE_TOKEN "$PII_TOKEN" \
    PII_HMAC_KEY_PHONE "$PII_PHONE" PII_HMAC_KEY_EMAIL "$PII_EMAIL" \
    PII_ENCRYPTION_KEY "$PII_FERNET" ENVIRONMENT production
fi

if [[ "$TIER" == "core" ]]; then
  write_env "$ROOT/identity-service/.env.production" \
    DB_HOST "$CORE_HOST" DB_PASSWORD "$CORE_PASS" DB_SSL true DB_SSL_CA_FILE "$ROOT/global-bundle.pem" \
    COGNITO_USER_POOL_ID "$COGNITO_POOL" COGNITO_APP_CLIENT_ID "$COGNITO_CLIENT" COGNITO_REGION "$REGION" \
    INTERNAL_SYNC_API_KEY "$(openssl rand -hex 24)" ENVIRONMENT production

  write_env "$ROOT/audit-log-service/.env.production" \
    DB_HOST "$CORE_HOST" DB_PASSWORD "$CORE_PASS" DB_SSL true DB_SSL_CA_FILE "$ROOT/global-bundle.pem" \
    AUDIT_LOG_API_KEY "$AUDIT_KEY" SQS_QUEUE_URL "$AUDIT_SQS" AWS_REGION "$REGION"

  write_env "$ROOT/crm-service/.env.production" \
    DB_HOST "$CORE_HOST" DB_PASSWORD "$CORE_PASS" DB_SSL true DB_SSL_CA_FILE "$ROOT/global-bundle.pem" \
    REDIS_HOST "$REDIS_HOST" REDIS_SSL true \
    COGNITO_USER_POOL_ID "$COGNITO_POOL" COGNITO_APP_CLIENT_ID "$COGNITO_CLIENT" \
    EVENTBRIDGE_AUDIT_BUS_NAME "$AUDIT_BUS" KMS_KEY_ID "$KMS_ARN" AWS_REGION "$REGION"

  chmod +x "$ROOT/deploy/production/"*.sh
  "$ROOT/deploy/production/deploy-core-ec2.sh"
fi

if [[ "$TIER" == "crm" ]]; then
  write_env "$ROOT/crm-service/.env.production" \
    DB_HOST "$CORE_HOST" DB_PASSWORD "$CORE_PASS" DB_SSL true DB_SSL_CA_FILE "$ROOT/global-bundle.pem" \
    REDIS_HOST "$REDIS_HOST" REDIS_SSL true \
    COGNITO_USER_POOL_ID "$COGNITO_POOL" COGNITO_APP_CLIENT_ID "$COGNITO_CLIENT" \
    IDENTITY_SERVICE_URL "http://${CORE_IP}:8000" \
    PII_VAULT_SERVICE_URL "http://${CORE_IP}:8004" \
    AUDIT_LOG_SERVICE_URL "http://${CORE_IP}:8005" \
    VOIP_GATEWAY_URL "http://${VOIP_IP}:8006" \
    MT_BRIDGE_SERVICE_URL "http://${MT_IP}:8003" \
    CLIENT_SERVICE_URL "http://client:8000" \
    CLIENT_SERVICE_TOKEN "$CLIENT_TOKEN" MT_BRIDGE_SERVICE_TOKEN "$MT_TOKEN" \
    PII_VAULT_SERVICE_TOKEN "$PII_TOKEN" AUDIT_LOG_API_KEY "$AUDIT_KEY" \
    EVENTBRIDGE_AUDIT_BUS_NAME "$AUDIT_BUS" KMS_KEY_ID "$KMS_ARN" \
    S3_RECORDINGS_BUCKET "$CALL_BUCKET" AWS_REGION "$REGION"

  write_env "$ROOT/client-service/.env.production" \
    DB_HOST "$CORE_HOST" DB_PASSWORD "$CORE_PASS" DB_SSL true DB_SSL_CA_FILE "$ROOT/global-bundle.pem" \
    REDIS_HOST "$REDIS_HOST" REDIS_SSL true \
    COGNITO_USER_POOL_ID "$COGNITO_POOL" COGNITO_REGION "$REGION" \
    MT_BRIDGE_SERVICE_URL "http://${MT_IP}:8003" MT_BRIDGE_SERVICE_TOKEN "$MT_TOKEN" \
    INTERNAL_SERVICE_TOKEN "$CLIENT_TOKEN" ENVIRONMENT production \
    S3_KYC_BUCKET "esafx-kyc-docs-production-${ACCOUNT_ID}" \
    S3_AGREEMENTS_BUCKET "esafx-signed-agreements-production-${ACCOUNT_ID}" \
    AWS_REGION "$REGION"

  chmod +x "$ROOT/deploy/production/"*.sh
  "$ROOT/deploy/production/deploy-crm-ec2.sh"
fi

if [[ "$TIER" == "voip" ]]; then
  write_env "$ROOT/voip-gateway-service/.env.production" \
    DB_HOST "$CORE_HOST" DB_PASSWORD "$CORE_PASS" DB_SSL true DB_SSL_CA_FILE "$ROOT/global-bundle.pem" \
    INTERNAL_TOKEN "$CLIENT_TOKEN" \
    PII_VAULT_SERVICE_URL "http://${CORE_IP}:8004" PII_VAULT_SERVICE_TOKEN "$PII_TOKEN" \
    AUDIT_LOG_SERVICE_URL "http://${CORE_IP}:8005" AUDIT_LOG_API_KEY "$AUDIT_KEY" \
    VOIP_PROVIDER mock ENVIRONMENT production \
    S3_RECORDINGS_BUCKET "$CALL_BUCKET" AWS_REGION "$REGION"

  chmod +x "$ROOT/deploy/production/"*.sh
  "$ROOT/deploy/production/deploy-voip-ec2.sh"
fi

echo "Bootstrap complete for tier=$TIER"
