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

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local dry_run="${4:-false}"
  if [[ ! -f "$file" ]]; then
    echo "Missing $file — copy from env example first." >&2
    return 1
  fi
  if [[ "$dry_run" == true ]]; then
    echo "[dry-run] would set $key in $file"
    return 0
  fi
  local escaped tmp
  escaped="$(compose_escape "$value")"
  local tmp out
  tmp="$(mktemp)"
  out="$(mktemp)"
  grep -Ev "^\s*${key}\s*=" "$file" > "$tmp" || true
  {
    cat "$tmp"
    echo "${key}=${escaped}"
  } >"$out"
  rm -f "$tmp"
  if [[ -f "$file" ]]; then
    chmod --reference="$file" "$out" 2>/dev/null || chmod 600 "$out"
    chown --reference="$file" "$out" 2>/dev/null || true
  else
    chmod 600 "$out"
  fi
  mv "$out" "$file"
}
