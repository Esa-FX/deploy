#!/usr/bin/env bash
# Set OpenTelemetry OTLP endpoint for crm-api (local ADOT collector on CRM EC2).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_SUFFIX="${ENV_SUFFIX:-production}"
CRM_ENV="$REPO_ROOT/crm-service/.env.${ENV_SUFFIX}"

if [[ ! -f "$CRM_ENV" ]]; then
  echo "Missing $CRM_ENV — copy from .env.${ENV_SUFFIX}.example first." >&2
  exit 1
fi

OTEL_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://otel-collector:4318}"
OTEL_SERVICE="${OTEL_SERVICE_NAME:-esafx-crm}"

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

set_env_var "$CRM_ENV" OTEL_EXPORTER_OTLP_ENDPOINT "$OTEL_ENDPOINT"
set_env_var "$CRM_ENV" OTEL_SERVICE_NAME "$OTEL_SERVICE"

echo "Synced OTEL env into $CRM_ENV (endpoint=$OTEL_ENDPOINT)"
echo "Recreate: docker compose -f deploy/${ENV_SUFFIX}/docker-compose.crm.yml up -d --force-recreate otel-collector crm-api"
