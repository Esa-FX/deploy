#!/usr/bin/env bash
# Deploy mt-bridge on dedicated staging EC2 (required for CRM client finance).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT/mt-bridge-service"

ENV_FILE="${ENV_FILE:-.env.staging}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

chmod +x deploy/ec2-deploy.sh
./deploy/ec2-deploy.sh

echo "==> mt-bridge ready on port ${MT_BRIDGE_PORT:-8003}"
curl -sf "http://127.0.0.1:${MT_BRIDGE_PORT:-8003}/health" && echo " OK"
