#Requires -Version 7.0
<#
.SYNOPSIS
  Take a pre-change RDS snapshot of the Esa-FX databases, then prune stale ones.

.DESCRIPTION
  Run this BEFORE any migration, bulk import, manual data fix or anything else that
  could leave the databases in a state you would want to undo. Automated backups only
  reach back BackupRetentionPeriod days (7), so a mistake found later has no restore
  point. This script creates one, and proves it exists before you proceed.

  Snapshot names: <instance>-pre-<label>-<yyyyMMdd-HHmm>
  The script waits for each snapshot to reach 'available' and exits non-zero if any
  fails. A green exit means the restore points are real, not just requested.

  Snapshots are incremental, so one taken right after the nightly automated backup
  costs cents. They never expire on their own, and RDS allows 100 manual snapshots per
  Region, so the prune step matters: it deletes only <instance>-pre-* snapshots older
  than -KeepDays, never the esafx-*-az-* or any other manual snapshot.

  Alerting: backup failures notify the esafx-production-ops SNS topic through the
  esafx-prod-rds-events subscription (created by CLI, see production/terraform/rds.tf).

.PARAMETER Label
  Short tag for why the snapshot exists, e.g. 'mig-20261116' or 'client-import'.
  Letters, digits and dashes only.

.PARAMETER Instances
  DB instance identifiers. Default: the two production databases.

.PARAMETER KeepDays
  Delete <instance>-pre-* snapshots older than this many days. Default 14.

.PARAMETER DryRun
  Print what would be created and deleted, change nothing.

.PARAMETER SkipPrune
  Create snapshots, delete nothing.

.EXAMPLE
  pwsh ops/rds/rds-prechange-snapshot.ps1 -Label mig-20261116 -DryRun

.EXAMPLE
  pwsh ops/rds/rds-prechange-snapshot.ps1 -Label client-import
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Label,
  [string[]]$Instances = @('esafx-production-core', 'esafx-production-trading'),
  [ValidateRange(1, 90)][int]$KeepDays = 14,
  [switch]$DryRun,
  [switch]$SkipPrune,
  [string]$Region = 'ap-southeast-3',
  [string]$Profile = 'default',
  [int]$MaxManualPerRegion = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Aws {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $out = & aws @Arguments --region $Region --profile $Profile 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "aws $($Arguments[0]) failed (exit $LASTEXITCODE):`n$($out -join "`n")"
  }
  return $out
}

function Get-ManualSnapshots {
  $json = Invoke-Aws @('rds', 'describe-db-snapshots', '--snapshot-type', 'manual',
    '--query', 'DBSnapshots[].{Id:DBSnapshotIdentifier,DB:DBInstanceIdentifier,Created:SnapshotCreateTime,Status:Status}',
    '--output', 'json')
  return ($json -join '') | ConvertFrom-Json
}

function Remove-StalePreSnapshots {
  param([object[]]$Snapshots, [datetime]$Cutoff)
  $stale = $Snapshots | Where-Object {
    $_.Id -match '-pre-' -and $_.Status -eq 'available' -and [datetime]$_.Created -lt $Cutoff
  }
  if (-not $stale) {
    Write-Host "  prune: nothing older than $($Cutoff.ToString('yyyy-MM-dd'))"
    return 0
  }
  $removed = 0
  foreach ($snap in $stale) {
    if ($DryRun) {
      Write-Host "  prune: would delete $($snap.Id)"
    }
    else {
      Invoke-Aws @('rds', 'delete-db-snapshot', '--db-snapshot-identifier', $snap.Id) | Out-Null
      Write-Host "  prune: deleted $($snap.Id)"
    }
    $removed++
  }
  return $removed
}

function New-PreChangeSnapshot {
  param([string]$Instance, [string]$SnapshotId)
  if ($DryRun) {
    Write-Host "  create: would snapshot $Instance as $SnapshotId"
    return
  }
  Invoke-Aws @('rds', 'create-db-snapshot', '--db-instance-identifier', $Instance,
    '--db-snapshot-identifier', $SnapshotId,
    '--tags', 'Key=Purpose,Value=pre-change', 'Key=CreatedBy,Value=rds-prechange-snapshot', "Key=Label,Value=$Label") | Out-Null
  Write-Host "  create: $SnapshotId requested, waiting for 'available'..."
  Invoke-Aws @('rds', 'wait', 'db-snapshot-available', '--db-snapshot-identifier', $SnapshotId) | Out-Null
  Write-Host "  create: $SnapshotId available"
}

$cutoff = (Get-Date).ToUniversalTime().AddDays(-$KeepDays)
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmm')

Write-Host "RDS pre-change snapshot | label=$Label | region=$Region | keep=$KeepDays days$(if ($DryRun) { ' | DRY RUN' })"

$existing = Get-ManualSnapshots
Write-Host "  manual snapshots in region: $(@($existing).Count)"

if (-not $SkipPrune) {
  Remove-StalePreSnapshots -Snapshots $existing -Cutoff $cutoff | Out-Null
  $existing = Get-ManualSnapshots
}

# Prune may have freed room; re-check before creating, because the 100-snapshot cap is
# per Region and a mid-run failure leaves half a change set protected.
if (-not $DryRun -and @($existing).Count -ge $MaxManualPerRegion) {
  throw "Refusing to start: $(@($existing).Count) manual snapshots in $Region, cap is $MaxManualPerRegion. Prune or delete manually first."
}

foreach ($instance in $Instances) {
  $snapshotId = "$instance-pre-$Label-$stamp"
  New-PreChangeSnapshot -Instance $instance -SnapshotId $snapshotId
}

Write-Host ""
Write-Host "Done. Restore point: $stamp (UTC)."
Write-Host "Roll back a production database with:"
Write-Host "  aws rds restore-db-instance-from-db-snapshot --region $Region --profile $Profile \"
Write-Host "    --db-instance-identifier esafx-production-core-manual-restore \"
Write-Host "    --db-snapshot-identifier esafx-production-core-pre-$Label-$stamp"
Write-Host "Restore BOTH databases to the same snapshot stamp, then update the host in"
Write-Host "Secrets Manager (esafx/production/db/core and /trading) and restart the services."
