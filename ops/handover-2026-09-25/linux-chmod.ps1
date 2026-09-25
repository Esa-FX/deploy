# Linux chmod for prod voip settings + the 7 secret/env files.
# Modes only (stat). Never prints file contents.
# Env files -> 600. Bind-mounted password -> 640 root:999. voip-cdr -> 750 999:999.

param(
    [string]$CoreInstanceId = 'i-0230b88ebf9b7adea',
    [string]$CrmInstanceId = 'i-06c9b4647a1fc8ee8',
    [string]$VoipInstanceId = 'i-081933f9f6a99b067'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

function New-ChmodBash {
    param(
        [string]$Mode,
        [string]$FileList,
        [string]$DirList
    )
    @"
set -euo pipefail
MODE='$Mode'
SAVE_DIR=/root
echo "utc=`$(date -u +%Y-%m-%dT%H:%M:%SZ) host=`$(hostname) mode=`$MODE"
stat_one() {
  if [ -e "`$1" ]; then stat -c '%a %U:%G %F %n' "`$1"; else echo "MISSING `$1"; fi
}
walk_paths() {
  local fn="`$1"
  while IFS= read -r p; do
    [ -n "`$p" ] || continue
    "`$fn" "`$p"
  done <<'PATHS'
$FileList
$DirList
PATHS
}
list_state() { walk_paths stat_one; }
dump_one() {
  if [ -e "`$1" ]; then
    stat -c '%a %U:%G %n' "`$1" >> "`$OUTFILE"
  fi
  return 0
}
restore_state() {
  local src
  src=`$(ls -1t `$SAVE_DIR/linux-chmod-before-*.txt 2>/dev/null | head -1 || true)
  test -n "`$src" || { echo 'no chmod capture on this host'; exit 1; }
  echo "restore_from=`$src"
  while IFS= read -r line; do
    [ -n "`$line" ] || continue
    mode=`$(echo "`$line" | awk '{print `$1}')
    ug=`$(echo "`$line" | awk '{print `$2}')
    path=`$(echo "`$line" | awk '{print `$3}')
    sudo chmod "`$mode" "`$path"
    sudo chown "`$ug" "`$path" || true
  done < "`$src"
}
echo '=== current ==='
list_state
if [ "`$MODE" = 'capture' ]; then
  OUTFILE=`$SAVE_DIR/linux-chmod-before-`$(date -u +%Y%m%dT%H%M%SZ).txt
  : > "`$OUTFILE"
  walk_paths dump_one
  echo "save=`$OUTFILE"
  exit 0
fi
if [ "`$MODE" = 'rollback' ]; then
  restore_state
  echo '=== after rollback ==='
  list_state
  exit 0
fi
OUTFILE=`$SAVE_DIR/linux-chmod-before-`$(date -u +%Y%m%dT%H%M%SZ).txt
: > "`$OUTFILE"
walk_paths dump_one
echo "save=`$OUTFILE"
apply_one() {
  local p="`$1"
  [ -e "`$p" ] || { echo "skip missing `$p"; return 0; }
  if [ -d "`$p" ]; then
    sudo chown 999:999 "`$p" 2>/dev/null || true
    sudo chmod 750 "`$p"
    return 0
  fi
  case "`$p" in
    */secrets/*)
      sudo chown root:999 "`$p" 2>/dev/null || sudo chown root:root "`$p"
      sudo chmod 640 "`$p"
      ;;
    *)
      sudo chmod 600 "`$p"
      ;;
  esac
}
walk_paths apply_one
echo '=== after apply ==='
list_state
"@
}

$coreFiles = @'
/opt/esafx/identity-service/.env.production
/opt/esafx/pii-vault-service/.env.production
/opt/esafx/audit-log-service/.env.production
'@.Trim()
$crmFiles = @'
/opt/esafx/crm-service/.env.production
/opt/esafx/client-service/.env.production
/opt/esafx/secrets/trading_db_password
'@.Trim()
$voipFiles = @'
/opt/esafx/voip-gateway-service/.env.production
/opt/esafx/voip-gateway-service/.env.staging
/opt/esafx/voip-gateway-service/.env
'@.Trim()
$voipDirs = '/opt/esafx/data/voip-cdr'

Write-Host '=== BEFORE-CAPTURE ==='
Write-Host 'Seven files + voip settings (modes only, no contents):'
Write-Host '  1-3 core: identity, pii-vault, audit-log .env.production'
Write-Host '  4-5 crm: crm-service + client-service .env.production'
Write-Host '  6 crm: /opt/esafx/secrets/trading_db_password'
Write-Host '  7 voip: voip-gateway-service/.env.production'
Write-Host '  voip settings: extra .env/.env.staging if present, and /opt/esafx/data/voip-cdr (today 777)'

$c1 = Send-SsmScript -InstanceId $CoreInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode capture -FileList $coreFiles -DirList '') -TimeoutSeconds 180
$c2 = Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode capture -FileList $crmFiles -DirList '') -TimeoutSeconds 180
$c3 = Send-SsmScript -InstanceId $VoipInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode capture -FileList $voipFiles -DirList $voipDirs) -TimeoutSeconds 180
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Save-HandoverCapture -Name "linux-chmod-core-$stamp.txt" -Content ([string]$c1.StandardOutputContent) | Out-Null
Save-HandoverCapture -Name "linux-chmod-crm-$stamp.txt" -Content ([string]$c2.StandardOutputContent) | Out-Null
Save-HandoverCapture -Name "linux-chmod-voip-$stamp.txt" -Content ([string]$c3.StandardOutputContent) | Out-Null

Confirm-HandoverStep 'chmod 600 on env files, 640 root:999 on trading_db_password, 750 on voip-cdr?'

Write-Host '=== APPLY ==='
Send-SsmScript -InstanceId $CoreInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode apply -FileList $coreFiles -DirList '') -TimeoutSeconds 180 | Out-Null
Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode apply -FileList $crmFiles -DirList '') -TimeoutSeconds 180 | Out-Null
Send-SsmScript -InstanceId $VoipInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode apply -FileList $voipFiles -DirList $voipDirs) -TimeoutSeconds 180 | Out-Null

Write-Host '=== VERIFY ==='
Send-SsmScript -InstanceId $CoreInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode capture -FileList $coreFiles -DirList '') -TimeoutSeconds 180 | Out-Null
Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode capture -FileList $crmFiles -DirList '') -TimeoutSeconds 180 | Out-Null
Send-SsmScript -InstanceId $VoipInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode capture -FileList $voipFiles -DirList $voipDirs) -TimeoutSeconds 180 | Out-Null
Write-Host 'Expect 600 on env files, 640 on trading_db_password, 750 on voip-cdr.'
Write-Host 'Next deploy-crm/deploy-voip still chmod 644/777 — patch those scripts or this reverts (BACKLOG).'

Write-Host '=== ROLLBACK ==='
$do = Read-Host 'Type ROLLBACK to restore previous modes now, or press Enter to skip'
if ($do -eq 'ROLLBACK') {
    Send-SsmScript -InstanceId $CoreInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode rollback -FileList $coreFiles -DirList '') -TimeoutSeconds 180 | Out-Null
    Send-SsmScript -InstanceId $CrmInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode rollback -FileList $crmFiles -DirList '') -TimeoutSeconds 180 | Out-Null
    Send-SsmScript -InstanceId $VoipInstanceId -Os Linux -ScriptBody (New-ChmodBash -Mode rollback -FileList $voipFiles -DirList $voipDirs) -TimeoutSeconds 180 | Out-Null
}
