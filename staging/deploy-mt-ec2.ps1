# Run on the MT Windows EC2 via SSM PowerShell (not on Linux app EC2).
#   aws ssm start-session --target <mt-instance-id> --region ap-southeast-3
#   cd C:\esafx\mt-bridge-service
#   .\deploy\ec2-deploy.ps1
#
# Or from repo root on that host:
#   .\deploy\staging\deploy-mt-ec2.ps1

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$MtRoot = Join-Path $RepoRoot 'mt-bridge-service'

if (-not (Test-Path $MtRoot)) {
  throw "Expected mt-bridge-service at $MtRoot — clone repo to C:\esafx first."
}

Set-Location $MtRoot
& (Join-Path $MtRoot 'deploy\ec2-deploy.ps1')
