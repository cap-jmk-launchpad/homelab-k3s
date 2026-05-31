#Requires -Version 5.1
<#
.SYNOPSIS
  Install persistent homelab desktop firewall (scheduled task + ProgramData copy).

.DESCRIPTION
  Copies firewall scripts to ProgramData and registers a scheduled task that re-runs
  windows-firewall-homelab-desktop-apply.ps1 after every boot (90s delay for WSL/Hyper-V).

  netsh rules are already persistent; Hyper-V/WSL mirrored rules often need re-apply
  after reboot when the virtual switch comes up.

.PARAMETER Uninstall
  Remove the scheduled task and optional ProgramData scripts.

.EXAMPLE
  .\scripts\windows-firewall-homelab-desktop-install.ps1
#>
[CmdletBinding()]
param(
    [switch]$Elevated,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$TaskName = 'Homelab-Desktop-Firewall-WSL'
$InstallDir = Join-Path $env:ProgramData 'Homelab\firewall'
$SourceDir = $PSScriptRoot
$ScriptNames = @(
    'windows-firewall-homelab-desktop-apply.ps1',
    'windows-firewall-homelab-desktop.ps1',
    'windows-firewall-homelab-desktop-hyperv.ps1'
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Elevated -and -not (Test-IsAdministrator)) {
    Write-Host 'Re-launching elevated (UAC) for install.'
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`""
    )
    if ($Uninstall) { $argList += '-Uninstall' }
    $argList += '-Elevated'
    $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait -PassThru
    exit $proc.ExitCode
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed scheduled task: $TaskName"
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed: $InstallDir"
    }
    exit 0
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
foreach ($name in $ScriptNames) {
    $src = Join-Path $SourceDir $name
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Error "Missing source script: $src"
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $name) -Force
}
Write-Host "Installed scripts to: $InstallDir"

$applyScript = Join-Path $InstallDir 'windows-firewall-homelab-desktop-apply.ps1'
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$applyScript`" -Elevated"

$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = 'PT90S'
$triggers = @($startupTrigger)

$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Description 'Re-apply homelab desktop Windows + Hyper-V firewall rules after boot (WSL mirrored).' `
    -Action $action `
    -Trigger $triggers `
    -Principal $principal `
    -Settings $settings | Out-Null

Write-Host "Registered scheduled task: $TaskName (AtStartup + 90s delay, SYSTEM)"
Write-Host 'Applying rules now...'
& $applyScript -Elevated
Write-Host ''
Write-Host 'Done. Rules persist in the firewall store; task re-applies Hyper-V/WSL rules after each reboot.'
Write-Host "Uninstall: .\scripts\windows-firewall-homelab-desktop-install.ps1 -Uninstall"
