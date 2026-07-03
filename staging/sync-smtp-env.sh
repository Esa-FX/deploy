#!/usr/bin/env bash
# Sync SMTP credentials from Secrets Manager into crm-service .env.staging.
# See deploy/production/sync-smtp-env.sh for secret JSON format.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SECRET_ID="${SECRET_ID:-esafx/staging/smtp}"
export ENV_SUFFIX=staging
exec "$SCRIPT_DIR/../production/sync-smtp-env.sh"
