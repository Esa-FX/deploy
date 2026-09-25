# Tighten Windows firewall on MT host: remove any-source :8003; keep VPC CIDR only.
param(
    [string]$VpcCidr = "10.0.0.0/16",
    [string]$RuleName = "esafx-mt-bridge-8003",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$anyRule = "mt-bridge-8003"
if (Get-NetFirewallRule -DisplayName $anyRule -ErrorAction SilentlyContinue) {
    if ($WhatIf) {
        Write-Host "[WhatIf] would remove firewall rule: $anyRule"
    } else {
        Remove-NetFirewallRule -DisplayName $anyRule
        Write-Host "Removed firewall rule: $anyRule"
    }
} else {
    Write-Host "Firewall rule $anyRule already absent — skip"
}

if (-not (Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)) {
    if ($WhatIf) {
        Write-Host "[WhatIf] would create $RuleName for TCP 8003 from $VpcCidr"
    } else {
        New-NetFirewallRule -DisplayName $RuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8003 -RemoteAddress $VpcCidr | Out-Null
        Write-Host "Created firewall rule $RuleName for $VpcCidr"
    }
} else {
    if ($WhatIf) {
        Write-Host "[WhatIf] would set $RuleName remote address to $VpcCidr"
    } else {
        Set-NetFirewallRule -DisplayName $RuleName -RemoteAddress $VpcCidr
        Write-Host "Updated $RuleName remote address to $VpcCidr"
    }
}

# Drop legacy duplicate if present (keep env VPC rule only)
$legacy = "ESAFX-MT-8003-from-VPC"
if (Get-NetFirewallRule -DisplayName $legacy -ErrorAction SilentlyContinue) {
    if ($WhatIf) {
        Write-Host "[WhatIf] would remove redundant rule: $legacy"
    } else {
        Remove-NetFirewallRule -DisplayName $legacy
        Write-Host "Removed redundant rule: $legacy"
    }
}

Write-Host "Firewall hardening complete for staging VPC $VpcCidr"
