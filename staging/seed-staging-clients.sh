#!/usr/bin/env bash
# Seed demo clients + trading data on staging app EC2.
# Prerequisites: mt-bridge deployed (esafx_trading migrated), TRADING_DB_* in crm-service/.env.staging
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/deploy/staging/docker-compose.app.yml"

cd "$REPO_ROOT"

if ! grep -q '^TRADING_DB_HOST=' "$REPO_ROOT/crm-service/.env.staging" 2>/dev/null; then
  echo "TRADING_DB_HOST missing — run: ./deploy/staging/sync-crm-trading-db-env.sh" >&2
  exit 1
fi

SEED_SCRIPT="$REPO_ROOT/crm-service/scripts/seed_clients.py"
if [[ ! -f "$SEED_SCRIPT" ]]; then
  echo "Missing $SEED_SCRIPT — in crm-service run: git fetch origin && git checkout staging && git pull origin staging" >&2
  exit 1
fi

echo "==> Rebuild crm-api (includes scripts/seed_clients.py; --no-cache avoids stale image layers)"
docker compose -f "$COMPOSE_FILE" build --no-cache crm-api

echo "==> Seed clients (core + esafx_trading; --reset removes prior seed-client rows)"
docker compose -f "$COMPOSE_FILE" run --rm --no-deps \
  -v "$REPO_ROOT/crm-service/scripts:/app/scripts:ro" \
  crm-api python scripts/seed_clients.py --reset "$@"

echo "Done. Check KPI report for the current month as a team leader."
