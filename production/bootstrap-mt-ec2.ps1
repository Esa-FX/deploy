# Bootstrap mt-bridge on production Windows MT EC2.
# Run via SSM: powershell -ExecutionPolicy Bypass -File C:\esafx\deploy\production\bootstrap-mt-ec2.ps1
param(
    [string]$Branch = "main",
    [string]$InstallRoot = "C:\esafx\mt-bridge-service",
    [string]$DeployRoot = "C:\esafx\deploy",
    [string]$TradingSecretId = "esafx/production/db/trading",
    [string]$Region = "ap-southeast-3"
)

$ErrorActionPreference = "Stop"

function Ensure-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) { return }
    Write-Host "==> Install Git for Windows"
    $gitExe = Join-Path $env:TEMP "Git-64-bit.exe"
    Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.45.1.windows.1/Git-2.45.1-64-bit.exe" -OutFile $gitExe
    Start-Process -FilePath $gitExe -ArgumentList "/VERYSILENT", "/NORESTART" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git install failed"
    }
}

function Ensure-AwsCli {
    $awsExe = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    if (Test-Path $awsExe) { return $awsExe }
    Write-Host "==> Install AWS CLI v2"
    $msi = Join-Path $env:TEMP "AWSCLIV2.msi"
    Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $msi, "/quiet", "/norestart" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Test-Path $awsExe)) { throw "AWS CLI install failed" }
    return $awsExe
}

Ensure-Git | Out-Null
$null = Ensure-AwsCli

function Ensure-Python312 {
    Refresh-SessionPath
    if (Get-Command python -ErrorAction SilentlyContinue) { return }
    foreach ($path in @(
        "C:\Program Files\Python312\python.exe",
        "C:\Program Files\Python313\python.exe"
    )) {
        if (Test-Path $path) { return }
    }
    Write-Host "==> Install Python 3.12"
    $pyExe = Join-Path $env:TEMP "python-3.12.8-amd64.exe"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe" -OutFile $pyExe
    Start-Process -FilePath $pyExe -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_pip=1" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        throw "Python install failed"
    }
}

function Refresh-SessionPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
}

Ensure-Python312 | Out-Null

function Get-GitHubCloneUrl {
    param([string]$Repo)
    $aws = Get-Command aws -ErrorAction SilentlyContinue
    if (-not $aws) { throw "aws CLI required for private repo clone" }
    $token = & aws secretsmanager get-secret-value `
        --secret-id esafx/production/github-clone `
        --region $Region `
        --query SecretString `
        --output text 2>$null
    if ($token) {
        return "https://x-access-token:${token}@github.com/Esa-FX/${Repo}.git"
    }
    return "https://github.com/Esa-FX/${Repo}.git"
}

if (-not (Test-Path "C:\esafx")) {
    New-Item -ItemType Directory -Force -Path "C:\esafx" | Out-Null
}

# Clone deploy repo (for this script on future runs)
if (-not (Test-Path "$DeployRoot\.git")) {
    Write-Host "==> Clone deploy"
    $deployUrl = Get-GitHubCloneUrl -Repo "deploy"
    git clone --branch $Branch --depth 1 $deployUrl $DeployRoot
    git -C $DeployRoot remote set-url origin "https://github.com/Esa-FX/deploy.git"
}

if (-not (Test-Path $InstallRoot)) {
    Write-Host "==> Clone mt-bridge-service"
    $mtUrl = Get-GitHubCloneUrl -Repo "mt-bridge-service"
    git clone --branch $Branch --depth 1 $mtUrl $InstallRoot
    git -C $InstallRoot remote set-url origin "https://github.com/Esa-FX/mt-bridge-service.git"
} else {
    Write-Host "==> Pull mt-bridge-service"
    Set-Location $InstallRoot
    git fetch origin
    git checkout $Branch
    git pull origin $Branch
}

Set-Location $InstallRoot

$envFile = Join-Path $InstallRoot ".env.staging"
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $InstallRoot ".env.staging.example") $envFile
}

Write-Host "==> Sync TRADING_DB_* from $TradingSecretId"
& (Join-Path $InstallRoot "deploy\sync-env-from-secrets.ps1") -SecretId $TradingSecretId -Region $Region -InstallAwsCli

Write-Host "==> Sync MT5 credentials from Secrets Manager (if configured)"
& (Join-Path $InstallRoot "deploy\sync-mt5-from-secrets.ps1") -SecretId "esafx/production/mt5-manager" -Region $Region -InstallAwsCli -ErrorAction SilentlyContinue

# Production runtime settings
$redisHost = "esafx-production-redis.jwmnjk.0001.apse3.cache.amazonaws.com"
$lines = Get-Content $envFile | Where-Object {
    $_ -notmatch '^\s*(ENVIRONMENT|PORT|MT_BRIDGE_PORT|REDIS_HOST|REDIS_PORT|REDIS_SSL|REDIS_PASSWORD|HOST|HEALTH_PORT)\s*='
}
$lines += @(
    "ENVIRONMENT=production",
    "HOST=0.0.0.0",
    "PORT=8003",
    "MT_BRIDGE_PORT=8003",
    "HEALTH_PORT=8080",
    "REDIS_HOST=$redisHost",
    "REDIS_PORT=6379",
    "REDIS_SSL=true",
    "REDIS_PASSWORD="
)
$lines | Set-Content -Path $envFile -Encoding utf8

Write-Host "==> Deploy mt-bridge"
& (Join-Path $InstallRoot "deploy\ec2-deploy.ps1")

Write-Host "MT bridge production bootstrap complete (verify MT5_* in .env.staging if dealer API needed)."
