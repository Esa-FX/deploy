#!/usr/bin/env bash
# Pair dummy Cognito+CRM clients to existing Meta ingest logins on staging.
# Does not fabricate trading deals. Does not touch production.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/deploy/staging/docker-compose.app.yml"
REGION="${AWS_REGION:-ap-southeast-3}"

cd "$REPO_ROOT"

SEED_SCRIPT="$REPO_ROOT/crm-service/scripts/seed_staging_portal_clients.py"
if [[ ! -f "$SEED_SCRIPT" ]]; then
  echo "Missing $SEED_SCRIPT — git pull crm-service first." >&2
  exit 1
fi

export CLIENT_AREA_COGNITO_USER_POOL_ID="${CLIENT_AREA_COGNITO_USER_POOL_ID:-ap-southeast-3_pvuDxqsmS}"
export CLIENT_AREA_COGNITO_REGION="${CLIENT_AREA_COGNITO_REGION:-ap-southeast-3}"
export MT5_SQL_SECRET_ID="${MT5_SQL_SECRET_ID:-esafx/staging/db/mt5-sql-export}"

echo "==> Seed portal clients from Meta ingest (no crm-api recreate)"
docker compose -f "$COMPOSE_FILE" run --rm --no-deps --user root \
  -e CLIENT_AREA_COGNITO_USER_POOL_ID \
  -e CLIENT_AREA_COGNITO_REGION \
  -e MT5_SQL_SECRET_ID \
  -e AWS_REGION="$REGION" \
  -e AWS_DEFAULT_REGION="$REGION" \
  -v /opt/esafx/global-bundle.pem:/opt/esafx/global-bundle.pem:ro \
  -v "$REPO_ROOT/crm-service/scripts:/app/scripts:ro" \
  crm-api bash -lc '
    /opt/venv/bin/pip install -q pymysql
    exec /opt/venv/bin/python scripts/seed_staging_portal_clients.py --fetch-sql "$@"
  ' -- "$@"
