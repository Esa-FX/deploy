#!/usr/bin/env bash
# Stop whatsapp-gateway and free host port 8007 before compose recreate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/staging/docker-compose.app.yml}"

echo "==> prepare whatsapp-gateway (release port 8007)"

docker compose -f "$COMPOSE_FILE" stop whatsapp-gateway 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" rm -f whatsapp-gateway 2>/dev/null || true
docker rm -f esafx-whatsapp-gateway 2>/dev/null || true

if command -v fuser >/dev/null 2>&1; then
  fuser -k 8007/tcp 2>/dev/null || true
fi

for _ in $(seq 1 10); do
  if ! ss -lntp 2>/dev/null | grep -q ':8007 '; then
    echo "==> port 8007 is free"
    exit 0
  fi
  sleep 1
done

echo "ERROR: port 8007 still in use:" >&2
ss -lntp 2>/dev/null | grep ':8007 ' || true
exit 1
