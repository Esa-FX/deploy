param(
    [string]$VpcCidr = "10.1.0.0/16",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot\..\staging\sync-mt-bridge-firewall.ps1" -VpcCidr $VpcCidr @PSBoundParameters
