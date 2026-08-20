#!/usr/bin/env bash
# Lookup production wiki EC2 and serve Esa-FX/wiki hover graph on :8080.
set -euo pipefail
REGION="${AWS_REGION:-ap-southeast-3}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JSON="$SCRIPT_DIR/ssm-deploy-wiki-graph.json"
INSTANCE="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=esafx-production-docmost" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)"
if [[ -z "$INSTANCE" || "$INSTANCE" == "None" ]]; then
  echo "no running esafx-production-docmost instance" >&2
  exit 1
fi
echo "instance $INSTANCE"
PAYLOAD="$(INSTANCE="$INSTANCE" JSON="$JSON" python3 - <<'PY'
import json, os
path = os.environ["JSON"]
with open(path, encoding="utf-8") as fh:
    body = json.load(fh)
body["InstanceIds"] = [os.environ["INSTANCE"]]
print(json.dumps(body))
PY
)"
aws ssm send-command --region "$REGION" --cli-input-json "$PAYLOAD"
