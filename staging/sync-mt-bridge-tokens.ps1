# Sync per-caller MT tokens and optional dealer webhook secret onto the Windows MT host.
# Writes C:\esafx\mt-bridge-service\.env.staging and copies to .env (deploy uses both).
param(
    [string]$InstallRoot = "C:\esafx\mt-bridge-service",
    [string]$Region = "ap-southeast-3",
    [string]$TokensSecretId = "esafx/staging/service-tokens",
    [string]$WebhookSecretId = "esafx/staging/mt-bridge-webhook",
    [switch]$IncludeDealerWebhook,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Get-SecretJson {
    param([string]$SecretId)
    $raw = aws secretsmanager get-secret-value --secret-id $SecretId --region $Region --query SecretString --output text
    if (-not $raw) { throw "Empty secret $SecretId" }
    return $raw | ConvertFrom-Json
}

function Set-EnvKeys {
    param(
        [string]$Path,
        [hashtable]$Pairs
    )
    if (-not (Test-Path $Path)) {
        throw "Missing env file: $Path"
    }
    $lines = Get-Content $Path
    foreach ($key in $Pairs.Keys) {
        $pattern = "^\s*$key\s*="
        $line = "$key=$($Pairs[$key])"
        if ($lines -match $pattern) {
            $lines = $lines | ForEach-Object {
                if ($_ -match $pattern) { $line } else { $_ }
            }
        } else {
            $lines += $line
        }
    }
    if ($WhatIf) {
        Write-Host "[WhatIf] would update keys in $Path : $($Pairs.Keys -join ', ')"
        return
    }
    $lines | Set-Content -Path $Path -Encoding utf8
}

$tokens = Get-SecretJson -SecretId $TokensSecretId
foreach ($k in @("mt_bridge_crm", "mt_bridge_client", "mt_bridge_admin")) {
    if (-not $tokens.$k) { throw "Missing key $k in $TokensSecretId" }
}

$updates = @{
    MT_BRIDGE_TOKEN_CRM   = [string]$tokens.mt_bridge_crm
    MT_BRIDGE_TOKEN_CLIENT = [string]$tokens.mt_bridge_client
    MT_BRIDGE_TOKEN_ADMIN = [string]$tokens.mt_bridge_admin
}

if ($IncludeDealerWebhook) {
    $wh = Get-SecretJson -SecretId $WebhookSecretId
    if (-not $wh.dealer_webhook) { throw "Missing dealer_webhook in $WebhookSecretId" }
    $updates["DEALER_WEBHOOK_SECRET"] = [string]$wh.dealer_webhook
}

$envStaging = Join-Path $InstallRoot ".env.staging"
$envRuntime = Join-Path $InstallRoot ".env"

Set-EnvKeys -Path $envStaging -Pairs $updates
if ($WhatIf) {
    Write-Host "[WhatIf] would copy .env.staging -> .env"
} else {
    Copy-Item -Path $envStaging -Destination $envRuntime -Force
}

Write-Host "MT bridge token env keys updated (values not logged). Redeploy mt-bridge if process is already running."
