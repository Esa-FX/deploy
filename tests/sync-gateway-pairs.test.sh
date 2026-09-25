#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/service-tokens-sync-lib.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-lib.sh"
# shellcheck source=scripts/service-tokens-sync-apply.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-apply.sh"

failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
pass() { echo "PASS $1"; }

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

assert_gateway_pairs_unchanged() {
  local label="$1"
  local crm="$2"
  local voip="$3"
  local wa="$4"
  local voip_gw_before="$5"
  local wa_gw_before="$6"
  local expect_wa="$7"

  if [[ "$(env_file_get "$crm" VOIP_GATEWAY_TOKEN)" == "$voip_gw_before" ]]; then
    pass "$label: crm VOIP_GATEWAY_TOKEN unchanged"
  else
    fail "$label: crm VOIP_GATEWAY_TOKEN unchanged"
  fi
  if [[ "$(env_file_get "$voip" INTERNAL_TOKEN)" == "$voip_gw_before" ]]; then
    pass "$label: voip INTERNAL_TOKEN unchanged"
  else
    fail "$label: voip INTERNAL_TOKEN unchanged"
  fi
  if [[ "$(env_file_get "$crm" VOIP_GATEWAY_TOKEN)" == "$(env_file_get "$voip" INTERNAL_TOKEN)" ]]; then
    pass "$label: voip gateway pair still matches"
  else
    fail "$label: voip gateway pair still matches"
  fi
  if [[ "$(grep -E '^VOIP_GATEWAY_TOKEN=' "$crm")" == "VOIP_GATEWAY_TOKEN=${voip_gw_before}" ]]; then
    pass "$label: crm VOIP_GATEWAY_TOKEN line unchanged"
  else
    fail "$label: crm VOIP_GATEWAY_TOKEN line unchanged"
  fi
  if [[ "$(grep -E '^INTERNAL_TOKEN=' "$voip")" == "INTERNAL_TOKEN=${voip_gw_before}" ]]; then
    pass "$label: voip INTERNAL_TOKEN line unchanged"
  else
    fail "$label: voip INTERNAL_TOKEN line unchanged"
  fi

  if [[ "$expect_wa" == true ]]; then
    if [[ "$(env_file_get "$crm" WHATSAPP_GATEWAY_TOKEN)" == "$wa_gw_before" ]]; then
      pass "$label: crm WHATSAPP_GATEWAY_TOKEN unchanged"
    else
      fail "$label: crm WHATSAPP_GATEWAY_TOKEN unchanged"
    fi
    if [[ "$(env_file_get "$wa" INTERNAL_TOKEN)" == "$wa_gw_before" ]]; then
      pass "$label: whatsapp INTERNAL_TOKEN unchanged"
    else
      fail "$label: whatsapp INTERNAL_TOKEN unchanged"
    fi
    if [[ "$(env_file_get "$crm" WHATSAPP_GATEWAY_TOKEN)" == "$(env_file_get "$wa" INTERNAL_TOKEN)" ]]; then
      pass "$label: whatsapp gateway pair still matches"
    else
      fail "$label: whatsapp gateway pair still matches"
    fi
    if [[ "$(grep -E '^WHATSAPP_GATEWAY_TOKEN=' "$crm")" == "WHATSAPP_GATEWAY_TOKEN=${wa_gw_before}" ]]; then
      pass "$label: crm WHATSAPP_GATEWAY_TOKEN line unchanged"
    else
      fail "$label: crm WHATSAPP_GATEWAY_TOKEN line unchanged"
    fi
    if [[ "$(grep -E '^INTERNAL_TOKEN=' "$wa")" == "INTERNAL_TOKEN=${wa_gw_before}" ]]; then
      pass "$label: whatsapp INTERNAL_TOKEN line unchanged"
    else
      fail "$label: whatsapp INTERNAL_TOKEN line unchanged"
    fi
  fi
}

run_fixture_sync() {
  local root="$1"
  local suffix="$2"
  local include_wa="$3"
  local json="$4"
  service_tokens_sync_apply "test/secret" "$json" "$root" "$suffix" false false "$include_wa"
}

# --- Staging: gateway tokens differ from client key; client key rotates ---
staging_root="$(mktemp -d)"
trap 'rm -rf "$staging_root"' EXIT
mkdir -p "$staging_root/crm-service" "$staging_root/client-service" "$staging_root/pii-vault-service" \
  "$staging_root/voip-gateway-service" "$staging_root/whatsapp-gateway-service"

ST_CRM="$staging_root/crm-service/.env.staging"
ST_CLIENT="$staging_root/client-service/.env.staging"
ST_PII="$staging_root/pii-vault-service/.env.staging"
ST_VOIP="$staging_root/voip-gateway-service/.env.staging"
ST_WA="$staging_root/whatsapp-gateway-service/.env.staging"

write_env "$ST_CRM" \
  CLIENT_SERVICE_TOKEN old-client-pair \
  VOIP_GATEWAY_TOKEN shared-voip-gw-token \
  WHATSAPP_GATEWAY_TOKEN shared-wa-gw-token \
  MT_BRIDGE_SERVICE_TOKEN mt-old \
  PII_VAULT_SERVICE_TOKEN pii-old-crm
write_env "$ST_CLIENT" INTERNAL_SERVICE_TOKEN old-client-pair MT_BRIDGE_SERVICE_TOKEN mt-cli-old
write_env "$ST_PII" SERVICE_TOKEN pii-old-svc
write_env "$ST_VOIP" INTERNAL_TOKEN shared-voip-gw-token CRM_INTERNAL_TOKEN ci-old PII_VAULT_SERVICE_TOKEN pii-old-v
write_env "$ST_WA" INTERNAL_TOKEN shared-wa-gw-token CRM_INTERNAL_TOKEN ci-old PII_VAULT_SERVICE_TOKEN pii-old-w

voip_gw_before="shared-voip-gw-token"
wa_gw_before="shared-wa-gw-token"

ROTATED_CLIENT='{"client":"brand-new-client-key","mt_bridge_crm":"mt-new","mt_bridge_client":"mt-cli-new","pii_vault":"pii-new"}'
run_fixture_sync "$staging_root" staging true "$ROTATED_CLIENT"

if [[ "$(env_file_get "$ST_CLIENT" INTERNAL_SERVICE_TOKEN)" == "brand-new-client-key" ]]; then
  pass "staging: client INTERNAL_SERVICE_TOKEN updated from client key"
else
  fail "staging: client INTERNAL_SERVICE_TOKEN updated from client key"
fi
if [[ "$(env_file_get "$ST_CRM" CLIENT_SERVICE_TOKEN)" == "brand-new-client-key" ]]; then
  pass "staging: crm CLIENT_SERVICE_TOKEN updated from client key"
else
  fail "staging: crm CLIENT_SERVICE_TOKEN updated from client key"
fi

assert_gateway_pairs_unchanged "staging after client rotation" "$ST_CRM" "$ST_VOIP" "$ST_WA" \
  "$voip_gw_before" "$wa_gw_before" true

# --- Production: no whatsapp ---
prod_root="$(mktemp -d)"
mkdir -p "$prod_root/crm-service" "$prod_root/client-service" "$prod_root/pii-vault-service" \
  "$prod_root/voip-gateway-service"

PR_CRM="$prod_root/crm-service/.env.production"
PR_CLIENT="$prod_root/client-service/.env.production"
PR_PII="$prod_root/pii-vault-service/.env.production"
PR_VOIP="$prod_root/voip-gateway-service/.env.production"

write_env "$PR_CRM" \
  CLIENT_SERVICE_TOKEN prod-client-old \
  VOIP_GATEWAY_TOKEN prod-voip-shared \
  WHATSAPP_GATEWAY_TOKEN unused-on-prod \
  MT_BRIDGE_SERVICE_TOKEN mt-p \
  PII_VAULT_SERVICE_TOKEN pii-p-crm
write_env "$PR_CLIENT" INTERNAL_SERVICE_TOKEN prod-client-old MT_BRIDGE_SERVICE_TOKEN mt-p-cli
write_env "$PR_PII" SERVICE_TOKEN pii-p-svc
write_env "$PR_VOIP" INTERNAL_TOKEN prod-voip-shared CRM_INTERNAL_TOKEN ci-p PII_VAULT_SERVICE_TOKEN pii-p-v

prod_voip_gw_before="prod-voip-shared"

run_fixture_sync "$prod_root" production false "$ROTATED_CLIENT"

assert_gateway_pairs_unchanged "production after client rotation" "$PR_CRM" "$PR_VOIP" "" \
  "$prod_voip_gw_before" "" false

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All gateway pair tests passed."
