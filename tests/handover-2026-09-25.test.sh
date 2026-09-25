#!/usr/bin/env bash
# Guardrail for ops/handover-2026-09-25 (no AWS). Fails if a required piece is missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../ops/handover-2026-09-25" && pwd)"

need_files=(
  README.md BACKLOG.md _lib.ps1
  p47-checks.ps1 staging-cleanup.ps1
  crm-api-restart.ps1 crm-api-logrotate.ps1
  windows-acl.ps1 linux-chmod.ps1
)
for f in "${need_files[@]}"; do
  test -f "$ROOT/$f" || { echo "missing $f"; exit 1; }
done

for s in p47-checks.ps1 staging-cleanup.ps1 crm-api-restart.ps1 crm-api-logrotate.ps1 windows-acl.ps1 linux-chmod.ps1; do
  for word in BEFORE VERIFY ROLLBACK; do
    grep -qi "$word" "$ROOT/$s" || { echo "$s missing $word"; exit 1; }
  done
done

grep -q "not exercised" "$ROOT/p47-checks.ps1" || { echo "p47-checks.ps1 must print not exercised"; exit 1; }
grep -q "C:\\\\esafx-acl-before-prod-20260925.txt" "$ROOT/windows-acl.ps1" || { echo "windows-acl missing emergency backup path"; exit 1; }
grep -q "icacls C:\\\\ /restore" "$ROOT/windows-acl.ps1" || { echo "windows-acl missing C:\\ restore warning"; exit 1; }
grep -q "qa-newuser2-staging" "$ROOT/staging-cleanup.ps1" || { echo "staging-cleanup missing qa-newuser2-staging"; exit 1; }
grep -q "rollback-stg-ed9b5e8-20260925-1520" "$ROOT/staging-cleanup.ps1" || { echo "staging-cleanup missing rollback tag"; exit 1; }
grep -q "PoolTimeout" "$ROOT/crm-api-restart.ps1" || { echo "crm-api-restart missing PoolTimeout"; exit 1; }
grep -q "json-file" "$ROOT/crm-api-logrotate.ps1" || { echo "crm-api-logrotate missing json-file"; exit 1; }

# Must not print secret payloads.
if grep -RIn "Write-Host.*SecretString" "$ROOT"/*.ps1; then
  echo "refuses Write-Host of SecretString"
  exit 1
fi

required_backlog=(
  "Windows ACL"
  "Linux chmod"
  "docker log rotation"
  "prerestart"
  "CloudTrail"
  "14-day"
  "MT5"
  "GitHub Actions"
  "private"
  "staging and prod DBs"
  "No CI"
  "11 PRs"
  "WhatsApp"
  "Sentry"
  "password sign-in"
  "Recording-sync"
  "UU PDP"
)
for item in "${required_backlog[@]}"; do
  grep -q "$item" "$ROOT/BACKLOG.md" || { echo "BACKLOG.md missing $item"; exit 1; }
done

grep -q "p47-checks.ps1 first" "$ROOT/README.md" || { echo "README must say p47-checks first"; exit 1; }

echo "handover-2026-09-25 checks ok"
