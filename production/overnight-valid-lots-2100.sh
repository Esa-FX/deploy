#!/usr/bin/env bash
# Overnight 21:00 Asia/Jakarta: deploy fast closed-lots, DB maintain, requeue recent deal sync.
set -euo pipefail
export TZ=Asia/Jakarta
LOG="${LOG:-/var/log/esafx-overnight-valid-lots.log}"
REGION="${AWS_REGION:-ap-southeast-3}"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1

echo "===== START $(date -Is) ====="
cd /opt/esafx

GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id esafx/production/github-clone --region "$REGION" --query SecretString --output text)
git_pull() {
  local name=$1 branch=$2
  local url="https://x-access-token:${GITHUB_TOKEN}@github.com/Esa-FX/${name}.git"
  git -C "$name" remote set-url origin "$url"
  git -C "$name" fetch origin "$branch"
  git -C "$name" checkout "$branch"
  git -C "$name" reset --hard "origin/$branch"
  git -C "$name" remote set-url origin "https://github.com/Esa-FX/${name}.git"
  git -C "$name" log -1 --oneline
}
git_pull crm-service main

echo "==> deploy crm-api (optimized closed-lots)"
docker compose -f deploy/production/docker-compose.crm.yml build crm-api
docker compose -f deploy/production/docker-compose.crm.yml up -d --force-recreate crm-api
sleep 25
curl -sf http://127.0.0.1:8001/ready
echo

echo "==> trading DB maintain + open_time backfill (position_id) + requeue sync"
aws secretsmanager get-secret-value --secret-id esafx/production/db/trading --region "$REGION" --query SecretString --output text >/tmp/tr_admin.json
cat >/tmp/overnight_db.py <<'PY'
import asyncio, asyncpg, ssl, json
s = json.load(open("/tmp/tr_admin.json"))

async def main():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    c = await asyncpg.connect(
        host=s["host"],
        port=int(s.get("port", 5432)),
        user=s["username"],
        password=s["password"],
        database=s["dbname"],
        ssl=ctx,
        timeout=60,
    )
    await c.execute("ALTER ROLE crm_trading_readonly SET statement_timeout = '8s'")
    print("role_timeout_ok")
    await c.execute(
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_deals_login_position "
        "ON trading.deals (login_id, position_id)"
    )
    print("index_ok")
    await c.execute("ANALYZE trading.deals")
    print("analyze_ok")

    ids = [
        r["login_id"]
        for r in await c.fetch(
            """
            SELECT DISTINCT login_id
            FROM trading.deals
            WHERE coalesce(close_time, open_time) >= now() - interval '90 days'
            ORDER BY login_id
            LIMIT 500
            """
        )
    ]
    print("active_logins", len(ids))

    if ids:
        status = await c.execute(
            """
            UPDATE trading.account_sync_state
            SET backfill_status = 'pending', updated_at = now()
            WHERE login_id = ANY($1::bigint[])
            """,
            ids,
        )
        print("requeue_sync", status)

    # Batched open_time fix via PositionID (recent OUTs only)
    status2 = await c.execute(
        """
        WITH ranked AS (
          SELECT o.deal_id,
            (
              SELECT d_in.open_time
              FROM trading.deals d_in
              WHERE d_in.login_id = o.login_id
                AND o.position_id > 0
                AND d_in.position_id = o.position_id
                AND d_in.direction = 'in'
                AND d_in.type IN ('buy', 'sell')
              ORDER BY d_in.open_time ASC
              LIMIT 1
            ) AS new_open
          FROM trading.deals o
          WHERE o.direction = 'out'
            AND o.type IN ('buy', 'sell')
            AND o.close_time IS NOT NULL
            AND o.open_time = o.close_time
            AND o.position_id > 0
            AND o.close_time >= now() - interval '90 days'
          LIMIT 5000
        )
        UPDATE trading.deals d
        SET open_time = r.new_open
        FROM ranked r
        WHERE d.deal_id = r.deal_id
          AND r.new_open IS NOT NULL
          AND r.new_open < d.close_time
        """
    )
    print("open_time_backfill", status2)
    await c.close()

asyncio.run(main())
PY
docker cp /tmp/tr_admin.json esafx-crm-api:/tmp/tr_admin.json
docker cp /tmp/overnight_db.py esafx-crm-api:/tmp/overnight_db.py
docker exec esafx-crm-api python /tmp/overnight_db.py

echo "==> smoke"
sleep 5
curl -sf http://127.0.0.1:8001/ready; echo
POOL=$(docker logs esafx-crm-api --since 3m 2>&1 | grep -c QueuePool || true)
echo "pool_errors_3m=$POOL"

rm -f /tmp/tr_admin.json /tmp/overnight_db.py
docker exec -u root esafx-crm-api rm -f /tmp/tr_admin.json /tmp/overnight_db.py || true
echo "===== END $(date -Is) ====="
