#!/usr/bin/env bash
# Clone mt-bridge on a fresh Windows MT EC2 and deploy (run via SSM PowerShell).
#   aws ssm start-session --target <mt-instance-id> --region ap-southeast-3
#   powershell -ExecutionPolicy Bypass -File C:\esafx\deploy\staging\bootstrap-mt-ec2.ps1
param(
    [string]$RepoUrl = "https://github.com/Esa-FX/mt-bridge-service.git",
    [string]$Branch = "main",
    [string]$InstallRoot = "C:\esafx\mt-bridge-service"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path "C:\esafx")) {
    New-Item -ItemType Directory -Force -Path "C:\esafx" | Out-Null
}

if (-not (Test-Path $InstallRoot)) {
    Write-Host "==> Clone $RepoUrl -> $InstallRoot"
    git clone --branch $Branch $RepoUrl $InstallRoot
} else {
    Write-Host "==> Pull latest in $InstallRoot"
    Set-Location $InstallRoot
    git fetch origin
    git checkout $Branch
    git pull origin $Branch
}

Set-Location $InstallRoot

if (-not (Test-Path ".env.staging")) {
    Write-Host "==> Sync TRADING_DB_* from Secrets Manager"
    .\deploy\sync-env-from-secrets.ps1 -InstallAwsCli
}

Write-Host "==> Deploy mt-bridge (migrations + uvicorn :8003)"
.\deploy\ec2-deploy.ps1

Write-Host ""
Write-Host "MT bridge deploy complete. From app EC2, set MT_BRIDGE_SERVICE_URL to this host private IP :8003"
Write-Host "Then run: /opt/esafx/deploy/staging/seed-staging-clients.sh"
