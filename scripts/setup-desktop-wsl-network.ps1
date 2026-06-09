#Requires -Version 5.1
<#
.SYNOPSIS
  Restore WSL mirrored networking on the desktop k3s worker so Prometheus can scrape :9100/:9400/:10250.

.DESCRIPTION
  Creates %USERPROFILE%\.wslconfig with networkingMode=mirrored (required for hostNetwork
  metrics on 192.168.10.31). Without mirrored mode WSL eth0 stays on 172.21.x NAT and
  LAN scrapes time out even when node-exporter pods are Running.

  After writing .wslconfig, shuts down WSL once so the next start picks up mirrored mode.
  Then runs windows-firewall-homelab-desktop-apply.ps1 (elevated) for netsh + Hyper-V rules.

.EXAMPLE
  cd C:\Users\Julian\Documents\Programming\beelink-cleanup
  .\scripts\setup-desktop-wsl-network.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipWslShutdown,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'
$WslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
$Desired = @'
[wsl2]
networkingMode=mirrored

[experimental]
hostAddressLoopback=true
'@

$current = if (Test-Path -LiteralPath $WslConfigPath) {
    Get-Content -LiteralPath $WslConfigPath -Raw
} else {
    ''
}

if ($current -notmatch 'networkingMode\s*=\s*mirrored') {
    Set-Content -LiteralPath $WslConfigPath -Value $Desired.TrimEnd() -NoNewline
    Write-Host "Wrote $WslConfigPath (networkingMode=mirrored)"
    $needsRestart = -not $SkipWslShutdown
} else {
    Write-Host ".wslconfig already has networkingMode=mirrored"
    $needsRestart = $false
}

if ($needsRestart) {
    Write-Host 'Shutting down WSL so mirrored networking takes effect on next start...'
    wsl --shutdown
    Start-Sleep -Seconds 3
    wsl -e true | Out-Null
    Write-Host 'WSL restarted. Verify: wsl -e ip -4 addr show eth0  (expect 192.168.10.31/24)'
}

if (-not $SkipFirewall) {
    $apply = Join-Path $PSScriptRoot 'windows-firewall-homelab-desktop-apply.ps1'
    if (-not (Test-Path -LiteralPath $apply)) {
        Write-Warning "Missing $apply — copy from homelab-k3s/scripts/"
    } else {
        & $apply
    }
}

Write-Host ''
Write-Host 'Verify from blackpearl:'
Write-Host '  nc -zv 192.168.10.31 9100'
Write-Host '  kubectl top node desktop'
Write-Host 'Grafana: http://grafana.homelab.lan/d/homelab-cluster-resources/homelab-cluster-resources'
