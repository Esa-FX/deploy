#!/usr/bin/env bash
# Stop whatsapp-gateway + waha before compose recreate.
# Host port 8007 is NOT used by the gateway (compose uses expose only).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/staging/docker-compose.app.yml}"

echo "==> prepare whatsapp-gateway + waha (stop containers; no host port reclaim)"

DATA_DIR="${REPO_ROOT}/data"
mkdir -p "$DATA_DIR/chat-media" "$DATA_DIR/waha-sessions"
chmod 777 "$DATA_DIR" "$DATA_DIR/chat-media" "$DATA_DIR/waha-sessions" 2>/dev/null || true

docker compose -f "$COMPOSE_FILE" stop -t 30 whatsapp-gateway waha 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" rm -f whatsapp-gateway waha 2>/dev/null || true
docker rm -f esafx-whatsapp-gateway esafx-waha 2>/dev/null || true

sleep 2
echo "==> whatsapp-gateway + waha stopped (health via docker exec … curl)"
