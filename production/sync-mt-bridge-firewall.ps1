param(
    [string]$VpcCidr = "10.1.0.0/16",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$params = @{
    VpcCidr = $VpcCidr
}
if ($WhatIf) {
    $params['WhatIf'] = $true
}
& "$PSScriptRoot\..\staging\sync-mt-bridge-firewall.ps1" @params
