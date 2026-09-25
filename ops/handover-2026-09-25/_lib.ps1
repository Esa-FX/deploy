# Shared helpers for ops/handover-2026-09-25/*.ps1
# PowerShell 5.1. AWS CLI: --profile default --region ap-southeast-3
# Never print secret values. Host clocks are UTC.

$script:HandoverAwsProfile = 'default'
$script:HandoverAwsRegion = 'ap-southeast-3'

function Get-HandoverCaptureDir {
    $dir = Join-Path $PSScriptRoot 'captures'
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    return $dir
}

function Protect-HandoverText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = $Text
    $t = [regex]::Replace($t, '(?i)(password|token|secret|authorization|x-api-key|api_key)\s*[:=]\s*\S+', '$1=[redacted]')
    $t = [regex]::Replace($t, '(?i)SecretString\s*.+', 'SecretString=[redacted]')
    $t = [regex]::Replace($t, 'x-access-token:[^@/\s]+', 'x-access-token:[redacted]')
    return $t
}

function Write-Redacted {
    param([string]$Text)
    Write-Host (Protect-HandoverText $Text)
}

function Save-HandoverCapture {
    param(
        [string]$Name,
        [string]$Content
    )
    $path = Join-Path (Get-HandoverCaptureDir) $Name
    Set-Content -Path $path -Value (Protect-HandoverText $Content) -Encoding UTF8
    Write-Host "before-capture: $path"
    return $path
}

function Confirm-HandoverStep {
    param([string]$Prompt)
    Write-Host ''
    Write-Host $Prompt
    $ans = Read-Host 'Type YES to continue'
    if ($ans -ne 'YES') {
        throw 'Aborted by operator (need YES).'
    }
}

function Invoke-AwsCli {
    param([string[]]$AwsArgs)
    $all = @('--profile', $script:HandoverAwsProfile, '--region', $script:HandoverAwsRegion) + $AwsArgs
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & aws @all 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $text = ($out | Out-String)
    if ($code -ne 0) {
        Write-Redacted $text
        throw "aws failed exit=$code cmd=$($AwsArgs[0..([Math]::Min(3, $AwsArgs.Length - 1))] -join ' ')"
    }
    return $text.TrimEnd()
}

function ConvertTo-Utf8Base64 {
    param([string]$Text)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Escape-JsonString {
    param([string]$Text)
    $t = $Text.Replace('\', '\\').Replace('"', '\"')
    $t = $t.Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return $t
}

function Send-SsmScript {
    param(
        [string]$InstanceId,
        [ValidateSet('Linux', 'Windows')][string]$Os,
        [string]$ScriptBody,
        [int]$TimeoutSeconds = 300
    )
    $doc = 'AWS-RunShellScript'
    $b64 = ConvertTo-Utf8Base64 $ScriptBody
    if ($Os -eq 'Linux') {
        $remote = "set -euo pipefail; echo $b64 | base64 -d | bash"
    } else {
        $doc = 'AWS-RunPowerShellScript'
        $remote = "`$b=[Convert]::FromBase64String('$b64'); Invoke-Expression ([Text.Encoding]::UTF8.GetString(`$b))"
    }
    $escaped = Escape-JsonString $remote
    $json = "{`"DocumentName`":`"$doc`",`"InstanceIds`":[`"$InstanceId`"],`"TimeoutSeconds`":$TimeoutSeconds,`"Parameters`":{`"commands`":[`"$escaped`"]}}"
    $tmp = Join-Path $env:TEMP ("handover-ssm-" + [guid]::NewGuid().ToString() + ".json")
    [IO.File]::WriteAllText($tmp, $json)
    $fileUri = 'file://' + ($tmp -replace '\\', '/')
    try {
        $raw = Invoke-AwsCli -AwsArgs @('ssm', 'send-command', '--cli-input-json', $fileUri, '--output', 'json')
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    $parsed = $raw | ConvertFrom-Json
    $cid = $parsed.Command.CommandId
    if (-not $cid) { throw 'ssm send-command returned no CommandId' }
    Write-Host "SSM command=$cid instance=$InstanceId os=$Os"
    return Wait-SsmInvocation -CommandId $cid -InstanceId $InstanceId -TimeoutSeconds $TimeoutSeconds
}

function Wait-SsmInvocation {
    param(
        [string]$CommandId,
        [string]$InstanceId,
        [int]$TimeoutSeconds
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $inv = $null
    $status = 'Pending'
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 4
        $raw = Invoke-AwsCli -AwsArgs @(
            'ssm', 'get-command-invocation',
            '--command-id', $CommandId,
            '--instance-id', $InstanceId,
            '--output', 'json'
        )
        $inv = $raw | ConvertFrom-Json
        $status = [string]$inv.Status
        if (@('Success', 'Failed', 'Cancelled', 'TimedOut', 'Undeliverable', 'Terminated') -contains $status) {
            break
        }
    }
    Write-Host "SSM status=$status command=$CommandId"
    Write-Host '--- stdout ---'
    Write-Redacted ([string]$inv.StandardOutputContent)
    if ($inv.StandardErrorContent) {
        Write-Host '--- stderr ---'
        Write-Redacted ([string]$inv.StandardErrorContent)
    }
    if ($status -ne 'Success') {
        throw "SSM $CommandId ended $status"
    }
    return $inv
}
