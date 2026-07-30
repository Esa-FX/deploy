#!/usr/bin/env bash
# Deploy all app-tier services on staging EC2 (identity → crm migrate → pii-vault → crm-api → client).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/staging/docker-compose.app.yml}"

cd "$REPO_ROOT"

CA_BUNDLE="${RDS_CA_BUNDLE:-/opt/esafx/global-bundle.pem}"
if [[ ! -f "$CA_BUNDLE" ]]; then
  echo "==> Download RDS CA bundle to $CA_BUNDLE"
  sudo mkdir -p "$(dirname "$CA_BUNDLE")"
  sudo curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o "$CA_BUNDLE"
  sudo chmod 644 "$CA_BUNDLE"
fi

require_env() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "Missing $f — copy from .env.staging.example and fill values." >&2
    exit 1
  fi
}

for svc in identity-service crm-service pii-vault-service client-service audit-log-service voip-gateway-service whatsapp-gateway-service; do
  require_env "$REPO_ROOT/$svc/.env.staging"
done

echo "==> identity migrations (rebuild image so env.py / migrations are current)"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build identity-migrate

echo "==> crm migrations (includes pii_vault schema)"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build crm-migrate

echo "==> client migrations"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build client-migrate

echo "==> audit-log migrations"
docker compose -f "$COMPOSE_FILE" --profile migrate run --rm --build audit-migrate

echo "==> sync crm-api trading DB env (readonly secret → .env.staging + password file)"
"$REPO_ROOT/deploy/staging/sync-crm-trading-db-env.sh"

echo "==> sync inter-service tokens (Secrets Manager → crm / client / pii-vault / voip .env.staging)"
"$REPO_ROOT/deploy/staging/sync-service-tokens-env.sh"
"$REPO_ROOT/deploy/staging/sync-smtp-env.sh" || true
"$REPO_ROOT/deploy/staging/sync-elevenlabs-env.sh" || true

WA_ENV="$REPO_ROOT/whatsapp-gateway-service/.env.staging"
if [[ -f "$WA_ENV" ]]; then
  echo "==> normalize whatsapp-gateway staging env (WAHA)"
  sed -i 's|^WHATSAPP_PROVIDER=.*|WHATSAPP_PROVIDER=waha|' "$WA_ENV"
  sed -i 's|^APP_NAME=.*|APP_NAME=esafx-whatsapp-gateway|' "$WA_ENV"
  grep -q '^WHATSAPP_PROVIDER=' "$WA_ENV" || echo 'WHATSAPP_PROVIDER=waha' >> "$WA_ENV"
  grep -q '^APP_NAME=' "$WA_ENV" || echo 'APP_NAME=esafx-whatsapp-gateway' >> "$WA_ENV"
  grep -q '^WAHA_BASE_URL=' "$WA_ENV" || echo 'WAHA_BASE_URL=http://waha:3000' >> "$WA_ENV"
  grep -q '^WAHA_DEFAULT_ENGINE=' "$WA_ENV" || echo 'WAHA_DEFAULT_ENGINE=NOWEB' >> "$WA_ENV"
  grep -q '^WAHA_MARK_READ_ON_CRM_OPEN=' "$WA_ENV" || echo 'WAHA_MARK_READ_ON_CRM_OPEN=true' >> "$WA_ENV"
  if ! grep -q '^WAHA_WEBHOOK_URL=.' "$WA_ENV"; then
    echo 'WAHA_WEBHOOK_URL=http://whatsapp-gateway:8007/webhooks/waha' >> "$WA_ENV"
  fi
  if ! grep -q '^WAHA_API_KEY=.' "$WA_ENV"; then
    WAHA_KEY="$(openssl rand -hex 24)"
    echo "WAHA_API_KEY=${WAHA_KEY}" >> "$WA_ENV"
    echo "==> generated WAHA_API_KEY in whatsapp-gateway .env.staging"
  fi
  # Drop legacy wwebjs keys if present
  sed -i '/^WWEBJS_AUTH_DIR=/d' "$WA_ENV" 2>/dev/null || true
fi

"$REPO_ROOT/deploy/staging/prepare-whatsapp-gateway.sh"

echo "==> reclaim docker disk before image builds"
"$REPO_ROOT/deploy/staging/prune-docker-disk.sh"

echo "==> build & start"
# Gateway is Docker-network only (expose 8007, no host publish). Never fuser -k 8007 —
# that kills MCP / other host listeners and does not help compose recreate.
docker compose -f "$COMPOSE_FILE" stop whatsapp-gateway 2>/dev/null || true
docker rm -f esafx-whatsapp-gateway 2>/dev/null || true

# Build one image at a time — parallel builds exhaust small EC2 disks.
export COMPOSE_PARALLEL_LIMIT="${COMPOSE_PARALLEL_LIMIT:-1}"
BUILD_SERVICES=(identity pii-vault audit-log voip-gateway whatsapp-gateway crm-api client)
for svc in "${BUILD_SERVICES[@]}"; do
  echo "==> build $svc"
  docker compose -f "$COMPOSE_FILE" build "$svc"
done

echo "==> pull WAHA image"
docker compose -f "$COMPOSE_FILE" pull waha

echo "==> backfill PII search_text (partial lead search)"
docker compose -f "$COMPOSE_FILE" run --rm -e PYTHONPATH=/app --entrypoint python pii-vault /app/scripts/backfill_search_text.py

docker compose -f "$COMPOSE_FILE" up -d identity pii-vault audit-log voip-gateway waha whatsapp-gateway crm-api client

echo "==> health"
curl -sf "http://127.0.0.1:8000/health" && echo " identity OK"
curl -sf "http://127.0.0.1:8004/health" && echo " pii-vault OK"
curl -sf "http://127.0.0.1:8005/health" && echo " audit-log OK"
curl -sf "http://127.0.0.1:8006/health" && echo " voip-gateway OK"
docker exec esafx-whatsapp-gateway curl -sf "http://localhost:8007/health" && echo " whatsapp-gateway OK"
docker exec esafx-waha curl -sf "http://localhost:3000/health" && echo " waha OK"
curl -sf "http://127.0.0.1:${CRM_PORT:-8001}/health" && echo " crm-api OK"
curl -sf "http://127.0.0.1:${CLIENT_PORT:-8002}/health" && echo " client OK"

echo "App tier deploy complete. Ensure MT_BRIDGE_SERVICE_URL points at mt EC2 before testing CRM finance."
