# Add docker json-file log rotation for prod crm-api.
# Takes effect on the next container recreate (not on docker restart).
# Pair with crm-api-restart.ps1 only if you also recreate; this script does not recreate.

param(
    [string]$CrmInstanceId = 'i-06c9b4647a1fc8ee8',
    [string]$ComposeFile = '/opt/esafx/deploy/production/docker-compose.crm.yml',
    [string]$MaxSize = '10m',
    [string]$MaxFile = '3'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

$before = @"
set -euo pipefail
COMPOSE='$ComposeFile'
echo "utc=`$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker inspect -f 'log_driver={{.HostConfig.LogConfig.Type}} log_opts={{json .HostConfig.LogConfig.Config}}' esafx-crm-api
LOG=`$(docker inspect -f '{{.LogPath}}' esafx-crm-api)
if [ -f "`$LOG" ]; then
  ls -l "`$LOG" | awk '{print "log_bytes=" `$5 " path=" `$9}'
else
  echo "log_bytes=0"
fi
echo "compose=`$COMPOSE"
grep -n 'crm-api:\|logging:\|max-size' "`$COMPOSE" | head -40
cp -a "`$COMPOSE" "`${COMPOSE}.bak-logrotate"
echo "backup=`${COMPOSE}.bak-logrotate"
"@

$apply = @"
set -euo pipefail
COMPOSE='$ComposeFile'
MAX_SIZE='$MaxSize'
MAX_FILE='$MaxFile'
python3 - <<'PY'
from pathlib import Path
import re, sys
path = Path("$ComposeFile")
text = path.read_text()
if re.search(r'^\s+logging:\s*$', text, re.M) and 'max-size' in text:
    print('logging_block_already_present')
    sys.exit(0)
needle = '  crm-api:\n'
if needle not in text:
    print('crm-api service not found')
    sys.exit(1)
block = '''  crm-api:
    logging:
      driver: json-file
      options:
        max-size: "%s"
        max-file: "%s"
''' % ("$MaxSize", "$MaxFile")
# ponytail: insert logging immediately under crm-api:. Next recreate picks it up.
text = text.replace(needle, block, 1)
path.write_text(text)
print('compose_patched')
PY
grep -n -A6 'crm-api:' "`$COMPOSE" | head -20
echo 'verify: container LogConfig unchanged until recreate'
docker inspect -f 'still_driver={{.HostConfig.LogConfig.Type}} still_opts={{json .HostConfig.LogConfig.Config}}' esafx-crm-api
"@

$rollback = @"
set -euo pipefail
COMPOSE='$ComposeFile'
BAK=`${COMPOSE}.bak-logrotate
test -f "`$BAK" || { echo 'missing compose backup'; exit 1; }
cp -a "`$BAK" "`$COMPOSE"
echo "restored `$COMPOSE from `$BAK"
grep -n 'logging:\|max-size' "`$COMPOSE" || echo 'no logging block (expected after rollback)'
"@

Write-Host '=== BEFORE-CAPTURE ==='
$cap = Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody $before -TimeoutSeconds 180
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Save-HandoverCapture -Name "crm-api-logrotate-before-$stamp.txt" -Content ([string]$cap.StandardOutputContent) | Out-Null

Confirm-HandoverStep "Patch $ComposeFile with json-file max-size=$MaxSize max-file=$MaxFile ? (no recreate)"

Write-Host '=== APPLY ==='
Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody $apply -TimeoutSeconds 180 | Out-Null

Write-Host '=== VERIFY ==='
Write-Host 'Compose should show logging.driver json-file. Running container keeps the old driver until recreate.'
Write-Host 'Next: recreate crm-api (crm-api-restart.ps1 only docker-restarts; use compose up -d --no-deps --force-recreate crm-api when you want rotation live).'

Write-Host '=== ROLLBACK ==='
Write-Host 'Restore the compose backup (does not undo a recreate that already happened):'
Write-Host $rollback
Write-Host 'To run rollback now, re-invoke this script is not enough — send the rollback block via SSM, or copy:'
$doRollback = Read-Host 'Type ROLLBACK to restore compose now, or press Enter to skip'
if ($doRollback -eq 'ROLLBACK') {
    Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody $rollback -TimeoutSeconds 120 | Out-Null
}
