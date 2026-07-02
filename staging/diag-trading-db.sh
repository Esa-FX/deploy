#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/deploy/staging/docker-compose.app.yml"
cd "$REPO_ROOT"

docker compose -f "$COMPOSE_FILE" exec -T crm-api python - <<'PY'
import asyncio
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import text

from app.core.database import async_session_factory
from app.services.trading_db import trading_read_session

JAKARTA = ZoneInfo("Asia/Jakarta")

async def main() -> None:
    today = datetime.now(JAKARTA).date()
    start_local = datetime(today.year, today.month, 1, tzinfo=JAKARTA)
    end_local = datetime(today.year, today.month, today.day, tzinfo=JAKARTA) + timedelta(days=1)
    start = start_local.astimezone(timezone.utc)
    end = end_local.astimezone(timezone.utc)
    print(f"Jakarta MTD UTC: [{start.isoformat()}, {end.isoformat()})")

    async with async_session_factory() as db:
        configured = True
        try:
            from app.core.config import get_settings
            configured = get_settings().trading_db_configured
        except Exception as exc:
            print("settings error:", exc)
        print("trading_db_configured:", configured)

        async with trading_read_session(db) as tdb:
            for label, sql in [
                ("accounts", "SELECT COUNT(*) FROM trading.trading_accounts WHERE deleted_at IS NULL"),
                ("txns_total", "SELECT COUNT(*) FROM trading.deposits_withdrawals"),
                ("txns_completed", "SELECT COUNT(*) FROM trading.deposits_withdrawals WHERE status='completed' AND executed_at IS NOT NULL"),
            ]:
                r = await tdb.execute(text(sql))
                print(label, r.scalar())

            r = await tdb.execute(
                text(
                    """
                    SELECT COUNT(*) FROM trading.deposits_withdrawals
                    WHERE status='completed' AND type='deposit'
                      AND executed_at >= :start AND executed_at < :end
                    """
                ),
                {"start": start, "end": end},
            )
            print("mtd_deposits", r.scalar())

            r = await tdb.execute(
                text(
                    """
                    SELECT login_id, client_code, type, amount, executed_at
                    FROM trading.deposits_withdrawals
                    WHERE status='completed' AND executed_at IS NOT NULL
                    ORDER BY executed_at DESC
                    LIMIT 3
                    """
                )
            )
            rows = r.mappings().all()
            print("latest_txns:", [dict(x) for x in rows])

asyncio.run(main())
PY
