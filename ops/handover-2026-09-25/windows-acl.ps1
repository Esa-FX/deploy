# Prod Windows ACL: lock the 5 .env* files under C:\esafx\mt-bridge-service only.
# Do NOT icacls C:\ — 2,259 folders inherit from C:\.
# Existing C:\ ACL dump: C:\esafx-acl-before-prod-20260925.txt (emergency undo only).

param(
    [string]$MtInstanceId = 'i-0e81a8ed0002d028e',
    [string]$InstallRoot = 'C:\esafx\mt-bridge-service',
    [string]$EmergencyBackup = 'C:\esafx-acl-before-prod-20260925.txt'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

$remote = @'
$ErrorActionPreference = 'Stop'
$root = 'C:\esafx\mt-bridge-service'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$save = "C:\esafx\mt-bridge-env-acl-before-$stamp.txt"
$emergency = 'C:\esafx-acl-before-prod-20260925.txt'

Write-Host "utc=$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
Write-Host "root=$root"
if (-not (Test-Path $root)) { throw "missing $root" }

$envFiles = @(Get-ChildItem -LiteralPath $root -Filter '.env*' -File)
Write-Host "env_file_count=$($envFiles.Count) (handover said 5)"
foreach ($f in $envFiles) { Write-Host "env_name=$($f.Name) bytes=$($f.Length)" }

Write-Host '=== BEFORE icacls (names only, no file contents) ==='
if ($envFiles.Count -gt 0) {
    icacls ($envFiles.FullName)
    icacls ($envFiles.FullName) /save $save
    Write-Host "acl_save=$save"
} else {
    throw 'no .env* files found'
}

if (Test-Path $emergency) {
    Write-Host "emergency_backup_present=$emergency (undo for a C:\-wide change ONLY: icacls C:\ /restore $emergency)"
} else {
    Write-Host "emergency_backup_missing=$emergency"
}

$mode = $env:HANDOVER_ACL_MODE
if ($mode -ne 'apply' -and $mode -ne 'rollback') {
    Write-Host 'mode=capture-only'
    exit 0
}

if ($mode -eq 'rollback') {
    if (-not (Test-Path $save)) {
        $prev = Get-ChildItem -LiteralPath 'C:\esafx' -Filter 'mt-bridge-env-acl-before-*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $prev) { throw 'no mt-bridge env ACL save to restore' }
        $save = $prev.FullName
    }
    Write-Host "restore_from=$save"
    icacls $root /restore $save
    Write-Host '=== AFTER restore ==='
    icacls ($envFiles.FullName)
    exit 0
}

Write-Host '=== APPLY (files only; inheritance disabled on .env* not on C:\) ==='
foreach ($f in $envFiles) {
    icacls $f.FullName /inheritance:d
    icacls $f.FullName /grant:r "NT AUTHORITY\SYSTEM:(F)" "BUILTIN\Administrators:(F)"
    icacls $f.FullName /remove:g "BUILTIN\Users" "Everyone" "Authenticated Users"
}
Write-Host '=== VERIFY ==='
icacls ($envFiles.FullName)
Write-Host "rollback_file=$save"
Write-Host 'rollback: icacls C:\esafx\mt-bridge-service /restore <rollback_file>'
Write-Host 'DO NOT run icacls C:\ /restore unless you changed C:\ itself.'
'@

Write-Host '=== BEFORE-CAPTURE ==='
$cap = Send-SsmScript -InstanceId $MtInstanceId -Os Windows -ScriptBody $remote -TimeoutSeconds 180
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Save-HandoverCapture -Name "windows-acl-before-$stamp.txt" -Content ([string]$cap.StandardOutputContent) | Out-Null

Write-Host ''
Write-Host "This locks only .env* under $InstallRoot on $MtInstanceId."
Write-Host "2,259 folders inherit from C:\ — this script never touches C:\."
Write-Host "Emergency C:\ dump (already on the host): $EmergencyBackup"
Write-Host 'Emergency undo (only if C:\ was changed): icacls C:\ /restore'

Confirm-HandoverStep "Apply ACL on the .env* files under $InstallRoot ?"

$apply = " `$env:HANDOVER_ACL_MODE = 'apply'`n" + $remote
Write-Host '=== APPLY ==='
Send-SsmScript -InstanceId $MtInstanceId -Os Windows -ScriptBody $apply -TimeoutSeconds 180 | Out-Null

Write-Host '=== VERIFY ==='
Send-SsmScript -InstanceId $MtInstanceId -Os Windows -ScriptBody $remote -TimeoutSeconds 180 | Out-Null

Write-Host '=== ROLLBACK ==='
$do = Read-Host 'Type ROLLBACK to restore the .env* ACLs now, or press Enter to skip'
if ($do -eq 'ROLLBACK') {
    $rb = " `$env:HANDOVER_ACL_MODE = 'rollback'`n" + $remote
    Send-SsmScript -InstanceId $MtInstanceId -Os Windows -ScriptBody $rb -TimeoutSeconds 180 | Out-Null
} else {
    Write-Host 'Later: set HANDOVER_ACL_MODE=rollback on the host script, or:'
    Write-Host '  icacls C:\esafx\mt-bridge-service /restore C:\esafx\mt-bridge-env-acl-before-TIMESTAMP.txt'
}
