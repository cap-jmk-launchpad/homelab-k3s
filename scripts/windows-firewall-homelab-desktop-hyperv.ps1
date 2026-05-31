#Requires -RunAsAdministrator
# Run via scripts/windows-firewall-homelab-desktop-apply.ps1 (auto-elevates).
# Opens Hyper-V firewall rules so LAN can reach WSL listeners on 2222/9100/10250.
#
# WSL mirrored mode blocks inbound by default (Hyper-V DefaultInboundAction=Block).
# Rules must omit -VMCreatorId (matches working "WSL Homelab SSH") and use RemoteAddresses Any.
# Port-specific VMCreatorId rules alone are not enough for 9100/10250 on some hosts.
$ErrorActionPreference = 'Stop'

$rules = @(
  @{ Name = 'WSL Homelab SSH'; Port = 2222 },
  @{ Name = 'WSL Homelab node-exporter'; Port = 9100 },
  @{ Name = 'WSL Homelab kubelet'; Port = 10250 },
  @{ Name = 'WSL Homelab DCGM exporter'; Port = 9400 },
  @{ Name = 'WSL Homelab NCCL ephemeral'; Port = '1024-65535' }
)

foreach ($rule in $rules) {
  $existing = Get-NetFirewallHyperVRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host "Hyper-V rule already exists: $($rule.Name)"
    continue
  }
  New-NetFirewallHyperVRule `
    -DisplayName $rule.Name `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPorts $rule.Port `
    -Action Allow `
    -RemoteAddresses Any | Out-Null
  Write-Host "Added Hyper-V: $($rule.Name) TCP $($rule.Port) (RemoteAddresses Any)"
}

Write-Host 'Done. Test from blackpearl: nc -zv 192.168.10.31 9100; kubectl top node desktop'
