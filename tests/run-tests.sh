#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/sync-service-tokens-env.test.sh"
"$DIR/sync-rotate-crm-internal.test.sh"
"$DIR/sync-gateway-pairs.test.sh"
