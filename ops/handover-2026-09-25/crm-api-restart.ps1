# Safe restart of prod esafx-crm-api for the recurring pool stall.
# Captures health + PoolTimeout counts before and after. Does not rebuild the image.

param(
    [string]$CrmInstanceId = 'i-06c9b4647a1fc8ee8',
    [string]$Container = 'esafx-crm-api'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

$probe = @"
set -euo pipefail
C='$Container'
echo "utc=`$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker inspect -f 'id={{.Id}} image={{.Config.Image}} status={{.State.Status}} started={{.State.StartedAt}} restarts={{.RestartCount}}' "`$C"
echo -n 'health='
curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/health || echo FAIL
echo
echo -n 'ready='
curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/ready || echo FAIL
echo
PT=`$(docker logs "`$C" --since 24h 2>&1 | grep -cF 'PoolTimeout' || true)
QP=`$(docker logs "`$C" --since 24h 2>&1 | grep -cF 'QueuePool' || true)
echo "PoolTimeout_24h=`$PT"
echo "QueuePool_24h=`$QP"
LOG=`$(docker inspect -f '{{.LogPath}}' "`$C")
if [ -f "`$LOG" ]; then
  ls -l "`$LOG" | awk '{print "log_bytes=" `$5}'
fi
"@

$restart = @"
set -euo pipefail
C='$Container'
STAMP=`$(date -u +%Y%m%dT%H%M%SZ)
OUT=/root/crm-api-handover-prerestart-`$STAMP.log
docker logs "`$C" --since 2h > "`$OUT" 2>&1 || true
echo "prerestart_log=`$OUT bytes=`$(wc -c < "`$OUT")"
docker restart "`$C"
sleep 20
echo -n 'health='
curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/health
echo
echo -n 'ready='
curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/ready || true
echo
docker inspect -f 'status={{.State.Status}} started={{.State.StartedAt}}' "`$C"
"@

Write-Host '=== BEFORE-CAPTURE ==='
$before = Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody $probe -TimeoutSeconds 180
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Save-HandoverCapture -Name "crm-api-restart-before-$stamp.txt" -Content ([string]$before.StandardOutputContent) | Out-Null

Confirm-HandoverStep "Restart $Container on $CrmInstanceId ? (no rebuild; ~20s health wait)"

Write-Host '=== RESTART ==='
Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody $restart -TimeoutSeconds 180 | Out-Null

Write-Host '=== VERIFY ==='
$after = Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody $probe -TimeoutSeconds 180
Save-HandoverCapture -Name "crm-api-restart-after-$stamp.txt" -Content ([string]$after.StandardOutputContent) | Out-Null
Write-Host 'Expect health=200 and ready=200. PoolTimeout_24h still includes pre-restart hits; watch the next hour.'

Write-Host '=== ROLLBACK ==='
Write-Host 'This is a process restart, not a version change. If health stays bad, restart once more:'
Write-Host "  docker restart $Container"
Write-Host 'If still bad, use production/ssm-rollback-one-service.json with the last good crm-service SHA.'
Write-Host 'Do not delete /root/crm-api-prerestart-20260925.log or the -1454- dump until the pool RCA is closed.'
