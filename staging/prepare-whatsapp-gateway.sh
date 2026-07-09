#!/usr/bin/env bash
# Stop whatsapp-gateway and free host port 8007 before compose recreate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/staging/docker-compose.app.yml}"

echo "==> prepare whatsapp-gateway (release port 8007)"

DATA_DIR="${REPO_ROOT}/data"
mkdir -p "$DATA_DIR/wwebjs_auth" "$DATA_DIR/chat-media"
chmod 777 "$DATA_DIR" "$DATA_DIR/wwebjs_auth" "$DATA_DIR/chat-media" 2>/dev/null || true

# Graceful stop so Chromium inside the container can exit before SIGKILL.
docker compose -f "$COMPOSE_FILE" stop -t 30 whatsapp-gateway 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" rm -f whatsapp-gateway 2>/dev/null || true
docker rm -f esafx-whatsapp-gateway 2>/dev/null || true

if command -v fuser >/dev/null 2>&1; then
  fuser -k 8007/tcp 2>/dev/null || true
fi

# Orphan node/chromium listeners can survive a failed recreate and block the port.
if command -v ss >/dev/null 2>&1; then
  for pid in $(ss -lntp 2>/dev/null | grep ':8007 ' | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u); do
    kill -9 "$pid" 2>/dev/null || true
  done
fi

# Chromium children sometimes outlive a quick docker stop on small instances.
if command -v pgrep >/dev/null 2>&1; then
  pkill -9 -f 'chromium.*wwebjs' 2>/dev/null || true
  pkill -9 -f 'node dist/index.js' 2>/dev/null || true
fi

sleep 2

for i in $(seq 1 30); do
  if ! ss -lntp 2>/dev/null | grep -q ':8007 '; then
    echo "==> port 8007 is free"
    exit 0
  fi
  if (( i % 5 == 0 )); then
    echo "==> waiting for port 8007 (${i}s)..."
    if command -v fuser >/dev/null 2>&1; then
      fuser -k 8007/tcp 2>/dev/null || true
    fi
  fi
  sleep 1
done

echo "ERROR: port 8007 still in use:" >&2
ss -lntp 2>/dev/null | grep ':8007 ' || true
exit 1
