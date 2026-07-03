#!/usr/bin/env bash
# Deploy VoIP tier on production voip EC2.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/deploy/production/docker-compose.voip.yml}"

cd "$REPO_ROOT"

require_env() {
  [[ -f "$1" ]] || { echo "Missing $1" >&2; exit 1; }
}

require_env "$REPO_ROOT/voip-gateway-service/.env.production"

echo "==> sync service tokens"
"$REPO_ROOT/deploy/production/sync-service-tokens-env.sh"

CA_BUNDLE="${RDS_CA_BUNDLE:-/opt/esafx/global-bundle.pem}"
if [[ ! -f "$CA_BUNDLE" ]]; then
  sudo mkdir -p "$(dirname "$CA_BUNDLE")"
  sudo curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -o "$CA_BUNDLE"
  sudo chmod 644 "$CA_BUNDLE"
fi

docker compose -f "$COMPOSE_FILE" build voip-gateway
docker compose -f "$COMPOSE_FILE" up -d voip-gateway

curl -sf "http://127.0.0.1:8006/health" && echo " voip-gateway OK"
echo "VoIP tier deploy complete. Whitelist terraform output voip_elastic_ip with vendor."
