#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/service-tokens-sync-lib.sh
source "$DEPLOY_ROOT/scripts/service-tokens-sync-lib.sh"

LABEL="esafx/test/service-tokens"
failures=0

assert_ok() {
  local name="$1"
  local json="$2"
  local key="$3"
  if out="$(require_service_token_key "$key" "$LABEL" "$json")"; then
    echo "PASS $name (got length ${#out})"
  else
    echo "FAIL $name (expected success)"
    failures=$((failures + 1))
  fi
}

assert_fail() {
  local name="$1"
  local json="$2"
  local key="$3"
  if require_service_token_key "$key" "$LABEL" "$json" >/dev/null 2>&1; then
    echo "FAIL $name (expected non-zero exit)"
    failures=$((failures + 1))
  else
    echo "PASS $name (rejected as expected)"
  fi
}

VALID='{"client":"abc123validtokenvalue","crm_internal":"x"}'
assert_ok "valid client key" "$VALID" "client"
assert_fail "missing key" "$VALID" "missing_key"
assert_fail "dev-internal-token" '{"client":"dev-internal-token"}' "client"
assert_fail "changeme placeholder" '{"client":"changeme"}' "client"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All require_service_token_key tests passed."
