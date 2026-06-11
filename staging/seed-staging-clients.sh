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

echo "==> Rebuild crm-api (includes scripts/seed_clients.py)"
docker compose -f "$COMPOSE_FILE" build crm-api

echo "==> Seed clients (core + esafx_trading)"
docker compose -f "$COMPOSE_FILE" run --rm --no-deps crm-api \
  python scripts/seed_clients.py --skip-pii "$@"

echo "Done. Check KPI report for the current month as a team leader."
