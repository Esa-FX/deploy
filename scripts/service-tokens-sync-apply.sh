# shellcheck shell=bash
# Apply service-tokens secret JSON to service .env files (sourced by sync scripts and tests).

service_tokens_sync_apply() {
  local secret_id="$1"
  local raw="$2"
  local repo_root="$3"
  local env_suffix="$4"
  local dry_run="$5"
  local rotate_crm_internal="$6"
  local include_whatsapp_crm_internal="$7"

  local crm_internal_token=""
  require_key() {
    require_service_token_key "$1" "$secret_id" "$raw"
  }

  local crm_env="${repo_root}/crm-service/.env.${env_suffix}"
  local client_env="${repo_root}/client-service/.env.${env_suffix}"
  local pii_env="${repo_root}/pii-vault-service/.env.${env_suffix}"
  local voip_env="${repo_root}/voip-gateway-service/.env.${env_suffix}"
  local wa_env="${repo_root}/whatsapp-gateway-service/.env.${env_suffix}"

  if [[ "$rotate_crm_internal" == true ]]; then
    local client_token
    client_token="$(require_key client)"
    crm_internal_token="$(require_key crm_internal)"
    if [[ "$crm_internal_token" == "$client_token" ]]; then
      echo "crm_internal must differ from client key" >&2
      return 1
    fi
    set_env_var_crm_internal "$crm_env" INTERNAL_SERVICE_TOKEN "$crm_internal_token" "$dry_run"
    set_env_var_crm_internal "$voip_env" CRM_INTERNAL_TOKEN "$crm_internal_token" "$dry_run"
    if [[ "$include_whatsapp_crm_internal" == true ]]; then
      set_env_var_crm_internal "$wa_env" CRM_INTERNAL_TOKEN "$crm_internal_token" "$dry_run"
    fi
    return 0
  fi

  local client_token mt_crm_token mt_client_token pii_token
  client_token="$(require_key client)"
  mt_crm_token="$(require_key mt_bridge_crm)"
  mt_client_token="$(require_key mt_bridge_client)"
  pii_token="$(require_key pii_vault)"

  set_client_pairing_var() {
    guard_client_pairing_key "$1" "$2" "$3" ""
    set_env_var "$1" "$2" "$3" "$dry_run"
  }

  set_client_pairing_var "$crm_env" CLIENT_SERVICE_TOKEN "$client_token"
  set_env_var "$crm_env" MT_BRIDGE_SERVICE_TOKEN "$mt_crm_token" "$dry_run"
  set_env_var "$crm_env" PII_VAULT_SERVICE_TOKEN "$pii_token" "$dry_run"
  # VOIP_GATEWAY_TOKEN / WHATSAPP_GATEWAY_TOKEN: keep existing in file (pair with gateway INTERNAL_TOKEN).

  set_client_pairing_var "$client_env" INTERNAL_SERVICE_TOKEN "$client_token"
  set_env_var "$client_env" MT_BRIDGE_SERVICE_TOKEN "$mt_client_token" "$dry_run"

  set_env_var "$pii_env" SERVICE_TOKEN "$pii_token" "$dry_run"
  set_client_pairing_var "$voip_env" INTERNAL_TOKEN "$client_token"
  set_env_var "$voip_env" PII_VAULT_SERVICE_TOKEN "$pii_token" "$dry_run"
  set_client_pairing_var "$wa_env" INTERNAL_TOKEN "$client_token"
  set_env_var "$wa_env" PII_VAULT_SERVICE_TOKEN "$pii_token" "$dry_run"
}

# Read a single KEY=value from an env file (no export). Empty if missing.
env_file_get() {
  local file="$1"
  local key="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true
}
