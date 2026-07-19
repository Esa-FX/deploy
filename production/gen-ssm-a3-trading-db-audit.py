#!/usr/bin/env python3
"""SSM: trading DB completeness audit on prod MT EC2.

Usage:
  python gen-ssm-a3-trading-db-audit.py --send
"""
from __future__ import annotations

import base64
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "mt-bridge-service" / "scripts" / "trading_db_audit.py"
OUT = Path(__file__).resolve().parent / "ssm-a3-trading-db-audit.json"
INSTANCE = "i-0e81a8ed0002d028e"


def main() -> None:
    script_b64 = base64.b64encode(SCRIPT.read_bytes()).decode()
    cmds = [
        "$ErrorActionPreference = 'Stop'",
        "Set-Location C:\\esafx\\mt-bridge-service",
        "$py = Join-Path (Get-Location) '.venv\\Scripts\\python.exe'",
        f"& $py -c \"import base64; open('scripts/trading_db_audit.py','wb').write(base64.b64decode('{script_b64}'))\"",
        "$env:PYTHONPATH = (Get-Location).Path",
        "Copy-Item -Path .env.staging -Destination .env -Force",
        "& $py scripts\\trading_db_audit.py",
    ]
    payload = {
        "DocumentName": "AWS-RunPowerShellScript",
        "InstanceIds": [INSTANCE],
        "TimeoutSeconds": 180,
        "Parameters": {"commands": cmds},
    }
    OUT.write_text(json.dumps(payload), encoding="utf-8")
    print(f"wrote {OUT}")
    if "--send" in sys.argv:
        result = subprocess.run(
            [
                "aws",
                "ssm",
                "send-command",
                "--region",
                "ap-southeast-3",
                "--cli-input-json",
                f"file://{OUT.as_posix()}",
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
