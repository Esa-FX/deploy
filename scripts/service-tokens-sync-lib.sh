# shellcheck shell=bash
# Shared helpers for sync-service-tokens-env.sh (source, do not execute).

require_service_token_key() {
  local key="$1"
  local secret_label="${2:-service-tokens}"
  python3 -c '
import json, sys

key = sys.argv[1]
label = sys.argv[2]
placeholders = {
    "dev-internal-token",
    "changeme",
    "change-me",
    "placeholder",
    "replace-me",
    "todo",
}
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    sys.stderr.write(f"Invalid JSON in {label}: {exc}\n")
    sys.exit(1)
if key not in data:
    sys.stderr.write(f"Secret key {key!r} is missing in {label}\n")
    sys.exit(1)
val = str(data[key]).strip()
if not val:
    sys.stderr.write(f"Secret key {key!r} is empty in {label}\n")
    sys.exit(1)
low = val.lower()
if low in placeholders or val in placeholders:
    sys.stderr.write(f"Secret key {key!r} is a placeholder in {label}\n")
    sys.exit(1)
print(val)
' "$key" "$secret_label" <<<"${3:-}"
}

compose_escape() {
  printf '%s' "$1" | sed 's/\$/$$/g'
}

_SET_ENV_VAR_TMP=""
_set_env_var_err() {
  if [[ -n "$_SET_ENV_VAR_TMP" && -f "$_SET_ENV_VAR_TMP" ]]; then
    rm -f "$_SET_ENV_VAR_TMP"
  fi
}

# Keys that must only ever receive the service-tokens "client" key (never crm_internal).
guard_client_pairing_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  local crm_internal_value="${4:-}"
  if [[ -n "$crm_internal_value" && "$value" == "$crm_internal_value" ]]; then
    echo "Refusing to set ${key} in ${file} from crm_internal (client-pairing key)" >&2
    exit 1
  fi
  case "$key" in
    CLIENT_SERVICE_TOKEN)
      [[ "$file" == *crm-service* ]] || {
        echo "CLIENT_SERVICE_TOKEN must only be set on crm-service env" >&2
        exit 1
      }
      ;;
    INTERNAL_SERVICE_TOKEN)
      [[ "$file" == *client-service* ]] || {
        echo "INTERNAL_SERVICE_TOKEN (client pairing) must only be set on client-service env" >&2
        exit 1
      }
      ;;
    INTERNAL_TOKEN)
      [[ "$file" == *voip-gateway* || "$file" == *whatsapp-gateway* ]] || {
        echo "INTERNAL_TOKEN must only be set on voip/whatsapp gateway env" >&2
        exit 1
      }
      ;;
  esac
}

# crm_internal rotation: only these file/key pairs (confirmed in application code).
set_env_var_crm_internal() {
  local file="$1"
  local key="$2"
  local value="$3"
  local dry_run="${4:-false}"
  local allowed=false
  if [[ "$key" == "INTERNAL_SERVICE_TOKEN" && "$file" == *crm-service* ]]; then
    allowed=true
  fi
  if [[ "$key" == "CRM_INTERNAL_TOKEN" && ( "$file" == *voip-gateway* || "$file" == *whatsapp-gateway* ) ]]; then
    allowed=true
  fi
  if [[ "$allowed" != true ]]; then
    echo "crm_internal must not be written to ${key} in ${file}" >&2
    exit 1
  fi
  set_env_var "$file" "$key" "$value" "$dry_run"
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local dry_run="${4:-false}"
  local dir escaped out
  if [[ ! -f "$file" ]]; then
    echo "Missing $file — copy from env example first." >&2
    return 1
  fi
  if [[ "$dry_run" == true ]]; then
    echo "[dry-run] would set $key in $file"
    return 0
  fi
  dir="$(dirname "$file")"
  escaped="$(compose_escape "$value")"
  out="$(mktemp "${dir}/.env-sync.XXXXXX")"
  _SET_ENV_VAR_TMP="$out"
  trap '_set_env_var_err' ERR
  grep -Ev "^\s*${key}\s*=" "$file" >"$out" || true
  echo "${key}=${escaped}" >>"$out"
  chmod 600 "$out"
  chown --reference="$file" "$out" 2>/dev/null || true
  mv -f "$out" "$file"
  _SET_ENV_VAR_TMP=""
  trap - ERR
}
