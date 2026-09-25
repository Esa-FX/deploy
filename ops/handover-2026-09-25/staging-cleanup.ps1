# Staging cleanup after identity #47 QA.
# 1) Delete Cognito users qa-newuser and qa-newuser2-staging from pool diSA1PdqG
# 2) Delete matching rows in the identity DB
# 3) Revert staging identity to #48 ed9b5e8 (image tag rollback-stg-ed9b5e8-20260925-1520)
# 4) Remove staging QA secrets (7-day recovery window)
# Each step confirms. Never prints secret values.

param(
    [string]$AppInstanceId = 'i-06e3745274ed0fac4',
    [string]$UserPoolId = 'ap-southeast-3_diSA1PdqG',
    [string[]]$QaUserNames = @('qa-newuser', 'qa-newuser2-staging'),
    [string]$IdentitySha = 'ed9b5e8',
    [string]$RollbackImage = 'esafx-identity:rollback-stg-ed9b5e8-20260925-1520',
    [string[]]$QaSecretIds = @(),
    [string]$QaSecretPrefix = 'esafx/staging/qa'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

function Get-CognitoUserCapture {
    param([string]$UserName)
    try {
        $raw = Invoke-AwsCli -AwsArgs @(
            'cognito-idp', 'admin-get-user',
            '--user-pool-id', $UserPoolId,
            '--username', $UserName,
            '--query', '{Username:Username,UserStatus:UserStatus,Enabled:Enabled,UserCreateDate:UserCreateDate}',
            '--output', 'json'
        )
        return "USER $UserName`n$raw"
    } catch {
        return "USER $UserName not found (already gone)"
    }
}

function Remove-CognitoQaUser {
    param([string]$UserName)
    try {
        Invoke-AwsCli -AwsArgs @(
            'cognito-idp', 'admin-delete-user',
            '--user-pool-id', $UserPoolId,
            '--username', $UserName
        ) | Out-Null
        return "deleted $UserName"
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'UserNotFoundException') { return "already gone $UserName" }
        throw
    }
}

Write-Host '=== BEFORE-CAPTURE + four confirmed steps ==='
Write-Host '=== STEP 1 Cognito users ==='
Write-Host "pool=$UserPoolId users=$($QaUserNames -join ', ')"
$cogBefore = New-Object System.Collections.Generic.List[string]
foreach ($u in $QaUserNames) { [void]$cogBefore.Add((Get-CognitoUserCapture $u)) }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Save-HandoverCapture -Name "staging-cognito-$stamp.txt" -Content ($cogBefore -join "`n") | Out-Null
Confirm-HandoverStep "Delete Cognito users $($QaUserNames -join ', ') from $UserPoolId ?"
foreach ($u in $QaUserNames) { Write-Host (Remove-CognitoQaUser $u) }
Write-Host 'VERIFY Cognito:'
foreach ($u in $QaUserNames) { Write-Host (Get-CognitoUserCapture $u) }
Write-Host 'ROLLBACK Cognito: cannot undelete. Re-create the QA user only if you still need it (no password was captured).'

$identityDbBash = @'
set -euo pipefail
echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker inspect -f 'identity image={{.Config.Image}} status={{.State.Status}}' esafx-identity
docker exec esafx-identity python - <<'PY'
import os, sys
from urllib.parse import quote_plus
os.environ.setdefault("PYTHONWARNINGS", "ignore")
NAMES = ("qa-newuser", "qa-newuser2-staging")
COL_OK = {"email", "username", "cognito_username", "cognito_sub", "login", "name"}
mode = os.environ.get("QA_DB_MODE", "count")

def url():
    for key in ("DATABASE_URL", "SQLALCHEMY_DATABASE_URI", "DB_URL"):
        v = os.environ.get(key)
        if v:
            return v.replace("postgresql+asyncpg", "postgresql").replace("postgresql+psycopg2", "postgresql")
    host = os.environ.get("DB_HOST") or os.environ.get("POSTGRES_HOST")
    if not host:
        print("no_db_env")
        sys.exit(2)
    user = os.environ.get("DB_USER") or os.environ.get("POSTGRES_USER") or "dbadmin"
    password = os.environ.get("DB_PASSWORD") or os.environ.get("POSTGRES_PASSWORD") or ""
    name = os.environ.get("DB_NAME") or os.environ.get("POSTGRES_DB") or os.environ.get("DB_DATABASE") or "esafx_core"
    port = os.environ.get("DB_PORT") or "5432"
    u = "postgresql://%s:%s@%s:%s/%s" % (quote_plus(user), quote_plus(password), host, port, name)
    if os.environ.get("DB_SSL", "").lower() in ("1", "true", "yes"):
        u += "?sslmode=require"
    return u

from sqlalchemy import create_engine, inspect, text
engine = create_engine(url())
insp = inspect(engine)
# ponytail: name-column scan, not identity admin API.
with engine.begin() as conn:
    for table in insp.get_table_names():
        cols = [c["name"] for c in insp.get_columns(table) if c["name"].lower() in COL_OK]
        if not cols:
            continue
        preds = []
        params = {}
        nparam = 0
        for col in cols:
            for name in NAMES:
                nparam += 1
                key = "p%d" % nparam
                preds.append("CAST(%s AS TEXT) = :%s" % (col, key))
                params[key] = name
        where = " OR ".join(preds)
        count = conn.execute(text("SELECT COUNT(*) FROM %s WHERE %s" % (table, where)), params).scalar()
        print("match table=%s count=%s" % (table, count))
        if mode == "delete" and count:
            conn.execute(text("DELETE FROM %s WHERE %s" % (table, where)), params)
            print("deleted table=%s" % table)
print("mode=%s" % mode)
PY
'@

Write-Host ''
Write-Host '=== STEP 2 identity DB rows ==='
$envCount = $identityDbBash
$dbBefore = Send-SsmScript -InstanceId $AppInstanceId -Os Linux -ScriptBody $envCount -TimeoutSeconds 180
Save-HandoverCapture -Name "staging-identity-db-$stamp.txt" -Content ([string]$dbBefore.StandardOutputContent) | Out-Null
Confirm-HandoverStep 'Delete matching qa-newuser rows from the staging identity DB? Counts are in the capture (no row dumps).'
$deleteBash = "export QA_DB_MODE=delete`n" + $identityDbBash
Send-SsmScript -InstanceId $AppInstanceId -Os Linux -ScriptBody $deleteBash -TimeoutSeconds 180 | Out-Null
Write-Host 'VERIFY identity DB (counts should be 0):'
Send-SsmScript -InstanceId $AppInstanceId -Os Linux -ScriptBody $envCount -TimeoutSeconds 180 | Out-Null
Write-Host 'ROLLBACK identity DB: no password dump was kept. Re-create the QA users in Cognito and let identity sync, or restore the staging RDS snapshot.'

$revertBefore = @'
set -euo pipefail
echo "utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo -n 'git_sha='
git -C /opt/esafx/identity-service rev-parse --short HEAD
echo -n 'git_head='
git -C /opt/esafx/identity-service log -1 --oneline
docker inspect -f 'image={{.Config.Image}} id={{.Image}} status={{.State.Status}}' esafx-identity
docker images esafx-identity --format 'tag={{.Tag}} id={{.ID}} created={{.CreatedSince}}'
curl -sf http://127.0.0.1:8000/health && echo ' health=ok' || echo ' health=FAIL'
'@

$revertApply = @"
set -euo pipefail
TAG='$RollbackImage'
SHA='$IdentitySha'
test -n "`$(docker images -q "`$TAG")" || { echo "missing image `$TAG"; docker images esafx-identity; exit 1; }
BEFORE_SHA=`$(git -C /opt/esafx/identity-service rev-parse HEAD)
echo "`$BEFORE_SHA" > /tmp/identity-sha-before-handover
docker inspect -f '{{.Image}}' esafx-identity > /tmp/identity-image-before-handover
cd /opt/esafx
TOKEN=`$(aws secretsmanager get-secret-value --secret-id esafx/staging/github-clone --region ap-southeast-3 --query SecretString --output text)
git -C identity-service remote set-url origin "https://x-access-token:`${TOKEN}@github.com/Esa-FX/identity-service.git"
git -C identity-service fetch --depth 50 origin
git -C identity-service checkout --detach "`$SHA"
git -C identity-service remote set-url origin "https://github.com/Esa-FX/identity-service.git"
unset TOKEN
git -C identity-service log -1 --oneline
export IDENTITY_IMAGE=`$TAG
docker compose -f deploy/staging/docker-compose.app.yml up -d --no-deps --no-build identity
sleep 15
curl -sf http://127.0.0.1:8000/health && echo ' health=ok'
docker inspect -f 'now_image={{.Config.Image}} status={{.State.Status}}' esafx-identity
"@

$revertUndo = @'
set -euo pipefail
if [ -f /tmp/identity-sha-before-handover ]; then
  SHA=$(cat /tmp/identity-sha-before-handover)
  echo "restore_sha=$SHA"
  git -C /opt/esafx/identity-service checkout --detach "$SHA" || true
fi
if [ -f /tmp/identity-image-before-handover ]; then
  IMG=$(cat /tmp/identity-image-before-handover)
  echo "restore_image=$IMG"
  docker tag "$IMG" esafx-identity:latest || true
  export IDENTITY_IMAGE=esafx-identity:latest
  docker compose -f /opt/esafx/deploy/staging/docker-compose.app.yml up -d --no-deps --no-build identity
  sleep 10
  curl -sf http://127.0.0.1:8000/health && echo ' health=ok'
fi
'@

Write-Host ''
Write-Host '=== STEP 3 revert staging identity to #48 ==='
Write-Host "sha=$IdentitySha image=$RollbackImage host=$AppInstanceId"
$imgBefore = Send-SsmScript -InstanceId $AppInstanceId -Os Linux -ScriptBody $revertBefore -TimeoutSeconds 180
Save-HandoverCapture -Name "staging-identity-image-$stamp.txt" -Content ([string]$imgBefore.StandardOutputContent) | Out-Null
Confirm-HandoverStep "Checkout identity $IdentitySha and recreate esafx-identity from $RollbackImage ?"
Send-SsmScript -InstanceId $AppInstanceId -Os Linux -ScriptBody $revertApply -TimeoutSeconds 300 | Out-Null
Write-Host 'VERIFY identity revert:'
Send-SsmScript -InstanceId $AppInstanceId -Os Linux -ScriptBody $revertBefore -TimeoutSeconds 180 | Out-Null
Write-Host 'ROLLBACK identity revert: re-run the captured previous SHA/image:'
Write-Host $revertUndo
Write-Host 'To execute rollback, pass that block via SSM (saved under captures).'

Write-Host ''
Write-Host '=== STEP 4 staging QA secrets ==='
$listRaw = Invoke-AwsCli -AwsArgs @(
    'secretsmanager', 'list-secrets',
    '--filters', "Key=name,Values=$QaSecretPrefix",
    '--query', 'SecretList[].Name',
    '--output', 'text'
)
$found = @()
if ($listRaw) {
    $found = @($listRaw -split '\s+' | Where-Object { $_ })
}
if ($QaSecretIds.Count -gt 0) { $found = @($found + $QaSecretIds | Select-Object -Unique) }
Write-Host "QA secret names (values not printed):"
if ($found.Count -eq 0) {
    Write-Host "(none with prefix $QaSecretPrefix)"
} else {
    $found | ForEach-Object { Write-Host " - $_" }
}
Save-HandoverCapture -Name "staging-qa-secrets-$stamp.txt" -Content (($found | ForEach-Object { $_ }) -join "`n") | Out-Null
if ($found.Count -eq 0) {
    Write-Host 'VERIFY secrets: nothing to delete. Pass -QaSecretIds if QA used another name.'
    Write-Host 'ROLLBACK secrets: n/a'
} else {
    Confirm-HandoverStep ("Schedule deletion (7-day recovery) for: " + ($found -join ', '))
    foreach ($name in $found) {
        Invoke-AwsCli -AwsArgs @(
            'secretsmanager', 'delete-secret',
            '--secret-id', $name,
            '--recovery-window-in-days', '7'
        ) | Out-Null
        Write-Host "scheduled_delete $name"
    }
    Write-Host 'VERIFY secrets: listed names now have a deletion date (values not printed).'
    Write-Host 'ROLLBACK secrets: aws secretsmanager restore-secret --secret-id <name>  (within 7 days)'
}
