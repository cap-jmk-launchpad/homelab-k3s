# Run elevated on desktop Windows host (WSL mirrored networking).
# Adds Hyper-V firewall rules so LAN can reach WSL listeners on 2222/9100/10250.
$ErrorActionPreference = 'Stop'
$remote = '192.168.10.0/24'
# WSL / Linux VM creator ID (Windows 11 mirrored mode)
$vmCreatorId = '{40E0FD32-5877-4D78-9C54-4D3F68CABC92}'

$rules = @(
  @{ Name = 'Homelab HyperV WSL SSH'; Port = 2222 },
  @{ Name = 'Homelab HyperV WSL kubelet'; Port = 10250 },
  @{ Name = 'Homelab HyperV WSL node-exporter'; Port = 9100 }
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
    -VMCreatorId $vmCreatorId `
    -Protocol TCP `
    -LocalPorts $rule.Port `
    -Action Allow `
    -RemoteAddresses $remote | Out-Null
  Write-Host "Added Hyper-V: $($rule.Name) TCP $($rule.Port) from $remote"
}

Write-Host 'Done. Test from blackpearl: nc -zv 192.168.10.31 9100'
