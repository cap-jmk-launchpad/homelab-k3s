#Requires -Version 5.1
<#
.SYNOPSIS
  Apply homelab desktop firewall rules (Windows + Hyper-V/WSL mirrored) in one elevated run.

.DESCRIPTION
  Runs windows-firewall-homelab-desktop.ps1 then windows-firewall-homelab-desktop-hyperv.ps1
  sequentially in the same Administrator session. Re-launches elevated when needed.

  For persistence across reboot (especially Hyper-V/WSL), run:
  windows-firewall-homelab-desktop-install.ps1

.EXAMPLE
  cd C:\Users\Julian\Documents\Programming\beelink-cleanup
  .\scripts\windows-firewall-homelab-desktop-apply.ps1
#>
[CmdletBinding()]
param(
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Elevated -and -not (Test-IsAdministrator)) {
    Write-Host 'Re-launching elevated (UAC). Approve the prompt, then both firewall layers will be applied.'
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-Elevated'
    )
    $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait -PassThru
    exit $proc.ExitCode
}

$desktop = Join-Path $ScriptDir 'windows-firewall-homelab-desktop.ps1'
$hyperv = Join-Path $ScriptDir 'windows-firewall-homelab-desktop-hyperv.ps1'
foreach ($path in @($desktop, $hyperv)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "Missing script: $path"
    }
}

Write-Host '==> Windows Advanced Firewall (netsh, LAN 192.168.10.0/24)'
& $desktop
Write-Host ''
Write-Host '==> Hyper-V firewall (WSL mirrored inbound)'
& $hyperv
Write-Host ''
Write-Host 'All homelab desktop firewall rules applied.'
