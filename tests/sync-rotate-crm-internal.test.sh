#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/service-tokens-sync-lib.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-lib.sh"
# shellcheck source=scripts/service-tokens-sync-apply.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-apply.sh"

failures=0
fail() {
  echo "FAIL $1"
  failures=$((failures + 1))
}
pass() {
  echo "PASS $1"
}

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

mkdir -p "$fixture_root/crm-service" \
  "$fixture_root/client-service" \
  "$fixture_root/pii-vault-service" \
  "$fixture_root/voip-gateway-service" \
  "$fixture_root/whatsapp-gateway-service"

write_env() {
  local file="$1"
  shift
  : >"$file"
  chmod 600 "$file"
  while [[ $# -ge 2 ]]; do
    echo "$1=$2" >>"$file"
    shift 2
  done
}

CRM="$fixture_root/crm-service/.env.staging"
CLIENT="$fixture_root/client-service/.env.staging"
PII="$fixture_root/pii-vault-service/.env.staging"
VOIP="$fixture_root/voip-gateway-service/.env.staging"
WA="$fixture_root/whatsapp-gateway-service/.env.staging"

write_env "$CRM" \
  INTERNAL_SERVICE_TOKEN old-crm-internal \
  CLIENT_SERVICE_TOKEN client-pair-abc \
  VOIP_GATEWAY_TOKEN voip-pair-xyz \
  WHATSAPP_GATEWAY_TOKEN wa-pair-uvw \
  MT_BRIDGE_SERVICE_TOKEN old-mt-crm \
  PII_VAULT_SERVICE_TOKEN old-pii

write_env "$CLIENT" \
  INTERNAL_SERVICE_TOKEN client-pair-abc \
  MT_BRIDGE_SERVICE_TOKEN old-mt-client

write_env "$PII" SERVICE_TOKEN old-pii-svc

write_env "$VOIP" \
  CRM_INTERNAL_TOKEN old-crm-internal \
  INTERNAL_TOKEN voip-pair-xyz \
  PII_VAULT_SERVICE_TOKEN old-pii-voip

write_env "$WA" \
  CRM_INTERNAL_TOKEN old-crm-internal \
  INTERNAL_TOKEN wa-pair-uvw \
  PII_VAULT_SERVICE_TOKEN old-pii-wa

snap_crm="$(mktemp)"
snap_client="$(mktemp)"
snap_voip="$(mktemp)"
snap_wa="$(mktemp)"
snap_pii="$(mktemp)"
cp "$CRM" "$snap_crm"
cp "$CLIENT" "$snap_client"
cp "$VOIP" "$snap_voip"
cp "$WA" "$snap_wa"
cp "$PII" "$snap_pii"

SECRET_JSON='{"client":"client-pair-abc","crm_internal":"new-crm-internal-secret","mt_bridge_crm":"x","mt_bridge_client":"y","pii_vault":"z"}'

service_tokens_sync_apply "test/secret" "$SECRET_JSON" "$fixture_root" staging false true true

if [[ "$(env_file_get "$CRM" INTERNAL_SERVICE_TOKEN)" == "new-crm-internal-secret" ]]; then
  pass "crm INTERNAL_SERVICE_TOKEN from crm_internal"
else
  fail "crm INTERNAL_SERVICE_TOKEN from crm_internal"
fi
if [[ "$(env_file_get "$VOIP" CRM_INTERNAL_TOKEN)" == "new-crm-internal-secret" ]]; then
  pass "voip CRM_INTERNAL_TOKEN from crm_internal"
else
  fail "voip CRM_INTERNAL_TOKEN from crm_internal"
fi
if [[ "$(env_file_get "$WA" CRM_INTERNAL_TOKEN)" == "new-crm-internal-secret" ]]; then
  pass "whatsapp CRM_INTERNAL_TOKEN from crm_internal (staging)"
else
  fail "whatsapp CRM_INTERNAL_TOKEN from crm_internal (staging)"
fi

if grep -q CRM_INTERNAL_TOKEN "$CLIENT" 2>/dev/null; then
  fail "client-service must not have CRM_INTERNAL_TOKEN"
else
  pass "client-service has no CRM_INTERNAL_TOKEN"
fi
if grep -q new-crm-internal-secret "$CLIENT" 2>/dev/null; then
  fail "client-service must not contain crm_internal value"
else
  pass "client-service does not contain crm_internal value"
fi

if cmp -s "$snap_client" "$CLIENT"; then pass "client env unchanged on rotate"; else fail "client env unchanged on rotate"; fi
if cmp -s "$snap_pii" "$PII"; then pass "pii env unchanged on rotate"; else fail "pii env unchanged on rotate"; fi

if [[ "$(env_file_get "$CRM" CLIENT_SERVICE_TOKEN)" == "client-pair-abc" ]]; then
  pass "crm CLIENT_SERVICE_TOKEN unchanged"
else
  fail "crm CLIENT_SERVICE_TOKEN unchanged"
fi
if [[ "$(env_file_get "$CRM" VOIP_GATEWAY_TOKEN)" == "voip-pair-xyz" ]]; then
  pass "crm VOIP_GATEWAY_TOKEN unchanged (keep-existing)"
else
  fail "crm VOIP_GATEWAY_TOKEN unchanged (keep-existing)"
fi
if [[ "$(env_file_get "$CRM" WHATSAPP_GATEWAY_TOKEN)" == "wa-pair-uvw" ]]; then
  pass "crm WHATSAPP_GATEWAY_TOKEN unchanged (keep-existing)"
else
  fail "crm WHATSAPP_GATEWAY_TOKEN unchanged (keep-existing)"
fi
if [[ "$(env_file_get "$CLIENT" INTERNAL_SERVICE_TOKEN)" == "client-pair-abc" ]]; then
  pass "client INTERNAL_SERVICE_TOKEN unchanged"
else
  fail "client INTERNAL_SERVICE_TOKEN unchanged"
fi
if [[ "$(env_file_get "$VOIP" INTERNAL_TOKEN)" == "voip-pair-xyz" ]]; then
  pass "voip INTERNAL_TOKEN unchanged"
else
  fail "voip INTERNAL_TOKEN unchanged"
fi
if [[ "$(env_file_get "$WA" INTERNAL_TOKEN)" == "wa-pair-uvw" ]]; then
  pass "whatsapp INTERNAL_TOKEN unchanged"
else
  fail "whatsapp INTERNAL_TOKEN unchanged"
fi
if [[ "$(env_file_get "$CRM" MT_BRIDGE_SERVICE_TOKEN)" == "old-mt-crm" ]]; then
  pass "crm MT_BRIDGE_SERVICE_TOKEN unchanged on rotate-only"
else
  fail "crm MT_BRIDGE_SERVICE_TOKEN unchanged on rotate-only"
fi

# Production rotate: no whatsapp file update
write_env "$WA" CRM_INTERNAL_TOKEN wa-only-old INTERNAL_TOKEN wa-pair-uvw PII_VAULT_SERVICE_TOKEN p
write_env "$VOIP" CRM_INTERNAL_TOKEN voip-old INTERNAL_TOKEN voip-pair-xyz PII_VAULT_SERVICE_TOKEN p
write_env "$CRM" INTERNAL_SERVICE_TOKEN crm-old CLIENT_SERVICE_TOKEN c VOIP_GATEWAY_TOKEN v WHATSAPP_GATEWAY_TOKEN w \
  MT_BRIDGE_SERVICE_TOKEN m PII_VAULT_SERVICE_TOKEN p

prod_root="$(mktemp -d)"
mkdir -p "$prod_root/crm-service" "$prod_root/client-service" "$prod_root/pii-vault-service" "$prod_root/voip-gateway-service"
PROD_CRM="$prod_root/crm-service/.env.production"
PROD_VOIP="$prod_root/voip-gateway-service/.env.production"
write_env "$PROD_CRM" INTERNAL_SERVICE_TOKEN old CLIENT_SERVICE_TOKEN c VOIP_GATEWAY_TOKEN v WHATSAPP_GATEWAY_TOKEN w MT_BRIDGE_SERVICE_TOKEN m PII_VAULT_SERVICE_TOKEN p
write_env "$PROD_VOIP" CRM_INTERNAL_TOKEN old-voip INTERNAL_TOKEN voip-in PII_VAULT_SERVICE_TOKEN p

service_tokens_sync_apply "test/secret" "$SECRET_JSON" "$prod_root" production false true false

if [[ "$(env_file_get "$PROD_CRM" INTERNAL_SERVICE_TOKEN)" == "new-crm-internal-secret" ]] &&
  [[ "$(env_file_get "$PROD_VOIP" CRM_INTERNAL_TOKEN)" == "new-crm-internal-secret" ]]; then
  pass "production rotate updates crm + voip only"
else
  fail "production rotate updates crm + voip only"
fi

# Normal sync must not rewrite crm gateway tokens
write_env "$CRM" \
  CLIENT_SERVICE_TOKEN keep-client \
  VOIP_GATEWAY_TOKEN keep-voip-gw \
  WHATSAPP_GATEWAY_TOKEN keep-wa-gw \
  MT_BRIDGE_SERVICE_TOKEN keep-mt \
  PII_VAULT_SERVICE_TOKEN keep-pii-crm
write_env "$CLIENT" INTERNAL_SERVICE_TOKEN keep-client MT_BRIDGE_SERVICE_TOKEN keep-mt-cli
write_env "$VOIP" INTERNAL_TOKEN keep-voip-in CRM_INTERNAL_TOKEN keep-crm-int PII_VAULT_SERVICE_TOKEN keep-pii-v
write_env "$WA" INTERNAL_TOKEN keep-wa-in CRM_INTERNAL_TOKEN keep-crm-int PII_VAULT_SERVICE_TOKEN keep-pii-w
write_env "$PII" SERVICE_TOKEN keep-pii-svc
SYNC_JSON='{"client":"new-client-secret","mt_bridge_crm":"new-mt-crm","mt_bridge_client":"new-mt-cli","pii_vault":"new-pii"}'
service_tokens_sync_apply "test/secret" "$SYNC_JSON" "$fixture_root" staging false false true

if [[ "$(env_file_get "$CRM" VOIP_GATEWAY_TOKEN)" == "keep-voip-gw" ]] &&
  [[ "$(env_file_get "$CRM" WHATSAPP_GATEWAY_TOKEN)" == "keep-wa-gw" ]]; then
  pass "normal sync keeps crm VOIP/WHATSAPP gateway tokens"
else
  fail "normal sync keeps crm VOIP/WHATSAPP gateway tokens"
fi
if [[ "$(env_file_get "$VOIP" INTERNAL_TOKEN)" == "keep-voip-in" ]]; then
  pass "normal sync keeps voip INTERNAL_TOKEN"
else
  fail "normal sync keeps voip INTERNAL_TOKEN"
fi
if [[ "$(env_file_get "$WA" INTERNAL_TOKEN)" == "keep-wa-in" ]]; then
  pass "normal sync keeps whatsapp INTERNAL_TOKEN"
else
  fail "normal sync keeps whatsapp INTERNAL_TOKEN"
fi
if [[ "$(env_file_get "$CRM" CLIENT_SERVICE_TOKEN)" == "new-client-secret" ]]; then
  pass "normal sync updates CLIENT_SERVICE_TOKEN"
else
  fail "normal sync updates CLIENT_SERVICE_TOKEN"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All rotate / pairing tests passed."
