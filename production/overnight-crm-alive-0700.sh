#!/usr/bin/env bash
# 07:00 Asia/Jakarta watchdog — if trading pool starving, re-enable closed-lots skip.
set -euo pipefail
export TZ=Asia/Jakarta
LOG="${LOG:-/var/log/esafx-overnight-valid-lots.log}"
exec >>"$LOG" 2>&1
echo "===== WATCHDOG $(date -Is) ====="
POOL=$(docker logs esafx-crm-api --since 30m 2>&1 | grep -c QueuePool || true)
SLOW=$(docker logs esafx-crm-api --since 30m 2>&1 | grep -c 'closed lots by login_id unavailable' || true)
echo "pool=$POOL slow_closed_lots=$SLOW"
if [ "${POOL:-0}" -ge 5 ] || [ "${SLOW:-0}" -ge 20 ]; then
  echo "UNHEALTHY — patching skip closed lots back on"
  docker exec esafx-crm-api python - <<'PY'
from pathlib import Path
import re
for rel in (
    "/app/app/services/trading_period_stats.py",
    "/app/app/services/client_trading_stats.py",
):
    path = Path(rel)
    if not path.exists():
        continue
    text = path.read_text()
    if "CRM_ALIVE_SKIP_CLOSED_LOTS" in text:
        print("already", rel)
        continue
    # inject after first metrics function docstring
    for fn in (
        "async def closed_lots_metrics_by_login_ids(",
        "async def closed_lots_metrics_by_client_codes(",
    ):
        if fn not in text:
            continue
        m = re.search(re.escape(fn) + r'[\s\S]*?"""[\s\S]*?"""\n', text)
        if not m:
            continue
        inject = m.group(0) + '    import os\n    if os.environ.get("CRM_ALIVE_SKIP_CLOSED_LOTS", "1") == "1":\n        return {}\n'
        text = text[: m.start()] + inject + text[m.end() :]
        path.write_text(text)
        print("patched", rel, fn)
        break
PY
  docker restart esafx-crm-api
  sleep 15
  curl -sf http://127.0.0.1:8001/ready || true
  echo
  echo "KILL_SWITCH_REENABLED"
else
  echo "OK — leave optimized closed-lots enabled"
fi
echo "===== WATCHDOG END $(date -Is) ====="
