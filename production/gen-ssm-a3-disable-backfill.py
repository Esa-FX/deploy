#!/usr/bin/env python3
"""Disable A3 auto-backfill on prod MT EC2 (steady-state after bulk history complete).

Usage:
  python gen-ssm-a3-disable-backfill.py --send
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

INSTANCE = "i-0e81a8ed0002d028e"
DIR = Path(__file__).resolve().parent

# Conservative throttle defaults for future manual / per-account FTD batches.
_ENV = {
    "AUTO_BACKFILL_ON_START": "false",
    "BACKFILL_ACCOUNTS_PER_BATCH": "1",
    "BACKFILL_DEAL_PAGES_PER_ACCOUNT": "2",
    "BACKFILL_BATCH_PAUSE_SECONDS": "60",
    "BACKFILL_CONCURRENCY_PER_READ_LOGIN": "1",
    "BACKFILL_RATE_PER_MINUTE_PER_LOGIN": "30",
    "BACKFILL_YIELD_TO_HOT_SYNC": "true",
}


def build_payload() -> dict:
    env_keys = "|".join(_ENV.keys())
    cmds = [
        "$ErrorActionPreference = 'Stop'",
        "$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')",
        "Set-Location C:\\esafx\\mt-bridge-service",
        "$envFile = '.env.staging'",
        f"$lines = Get-Content $envFile | Where-Object {{ $_ -notmatch '^\\s*({env_keys})\\s*=' }}",
    ]
    for key, value in _ENV.items():
        cmds.append(f"$lines += '{key}={value}'")
    cmds.extend(
        [
            "$lines | Set-Content $envFile -Encoding utf8",
            "Write-Host '==> A3 backfill disabled (steady state) ==>'",
            f"Get-Content $envFile | Where-Object {{ $_ -match '^\\s*({env_keys})\\s*=' }}",
            "Copy-Item -Path .env.staging -Destination .env -Force",
            "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -like '*uvicorn*app.main*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }",
            "Start-Sleep -Seconds 2",
            "Start-Process -FilePath '.venv\\Scripts\\uvicorn.exe' -ArgumentList 'app.main:app','--host','0.0.0.0','--port','8003' -WorkingDirectory (Get-Location) -WindowStyle Hidden",
            "Start-Sleep -Seconds 15",
            "Write-Host '--- health ---'",
            "try { (Invoke-RestMethod http://127.0.0.1:8003/health -TimeoutSec 15) | ConvertTo-Json } catch { Write-Host health_err=$($_.Exception.Message) }",
            "Write-Host '--- sync status ---'",
            "$headers = @{ Authorization = 'Bearer trial' }",
            "try { (Invoke-RestMethod http://127.0.0.1:8003/api/v1/mt/sync/status -Headers $headers -TimeoutSec 120) | ConvertTo-Json -Depth 6 } catch { Write-Host status_err=$($_.Exception.Message) }",
            "Write-Host A3_backfill_disabled",
        ]
    )
    return {
        "DocumentName": "AWS-RunPowerShellScript",
        "InstanceIds": [INSTANCE],
        "TimeoutSeconds": 900,
        "Parameters": {"commands": cmds},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Disable A3 auto-backfill on prod MT EC2")
    parser.add_argument("--send", action="store_true", help="Send SSM command to MT EC2")
    args = parser.parse_args()

    out = DIR / "ssm-a3-disable-backfill.json"
    payload = build_payload()
    out.write_text(json.dumps(payload), encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size} bytes)")

    if args.send:
        result = subprocess.run(
            [
                "aws",
                "ssm",
                "send-command",
                "--region",
                "ap-southeast-3",
                "--cli-input-json",
                f"file://{out.as_posix()}",
                "--query",
                "Command.CommandId",
                "--output",
                "text",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        print(result.stdout.strip())
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            sys.exit(result.returncode)


if __name__ == "__main__":
    main()
