#!/usr/bin/env bash
# Stop whatsapp-gateway container before compose recreate.
# Host port 8007 is NOT used by the gateway (compose uses expose only).
# Do NOT run `fuser -k 8007/tcp` — MCP and other host tools often bind 8007;
# killing them causes false "port conflict" failures and does not free Docker.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/staging/docker-compose.app.yml}"

echo "==> prepare whatsapp-gateway (stop container; no host port reclaim)"

DATA_DIR="${REPO_ROOT}/data"
mkdir -p "$DATA_DIR/wwebjs_auth" "$DATA_DIR/chat-media"
chmod 777 "$DATA_DIR" "$DATA_DIR/wwebjs_auth" "$DATA_DIR/chat-media" 2>/dev/null || true

docker compose -f "$COMPOSE_FILE" stop -t 30 whatsapp-gateway 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" rm -f whatsapp-gateway 2>/dev/null || true
docker rm -f esafx-whatsapp-gateway 2>/dev/null || true

sleep 2
echo "==> whatsapp-gateway container stopped (health via: docker exec … curl localhost:8007/health)"
