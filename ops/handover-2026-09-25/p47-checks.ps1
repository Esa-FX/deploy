# Read-only prod identity checks for #47 (password-reset lockout / global sign-out).
# Owner PC: PowerShell 5.1, AWS CLI --profile default --region ap-southeast-3
# Does not change anything. Rollback is a no-op.

param(
    [string]$CoreInstanceId = 'i-0230b88ebf9b7adea',
    [string]$SinceUtc = '2026-09-25T09:37:03Z',
    [string]$Container = 'esafx-identity'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

$bash = @"
set -euo pipefail
SINCE='$SinceUtc'
C='$Container'
echo "host=`$(hostname) utc=`$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "container=`$C since=`$SINCE"
docker inspect -f 'id={{.Id}} image={{.Config.Image}} started={{.State.StartedAt}} status={{.State.Status}}' "`$C"
echo '--- counts (fixed strings) ---'
count_fixed() {
  local label="`$1" needle="`$2"
  local n
  n=`$(docker logs "`$C" --since "`$SINCE" 2>&1 | grep -cF "`$needle" || true)
  printf '%s=%s\n' "`$label" "`$n"
}
count_fixed 'lockout_clear_disable' 'Lockout clear disable after password reset failed'
count_fixed 'lockout_clear_enable' 'Lockout clear enable after password reset failed'
count_fixed 'global_sign_out' 'Global sign-out after password reset failed'
count_fixed 'access_denied' 'AccessDenied'
echo '--- reset-password requests ---'
RESET=`$(docker logs "`$C" --since "`$SINCE" 2>&1 | grep -ciE 'reset-password|reset_password|/password/reset|password reset request' || true)
echo "reset_password_requests=`$RESET"
if [ "`$RESET" -eq 0 ]; then
  echo 'not exercised'
fi
echo '--- done (read-only) ---'
"@

Write-Host '=== BEFORE-CAPTURE (read-only metadata) ==='
$before = Send-SsmScript -InstanceId $CoreInstanceId -Os Linux -ScriptBody $bash -TimeoutSeconds 180
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Save-HandoverCapture -Name "p47-checks-$stamp.txt" -Content ([string]$before.StandardOutputContent) | Out-Null

Write-Host ''
Write-Host '=== VERIFY ==='
Write-Host 'Counts above are from prod identity logs since the #47 cutover timestamp.'
Write-Host "If reset_password_requests=0 the script prints 'not exercised'."

Write-Host ''
Write-Host '=== ROLLBACK ==='
Write-Host 'Read-only. Nothing to roll back.'
