# Run in elevated PowerShell on the desktop Windows host.
# Opens inbound TCP from the homelab LAN for WSL SSH, kubelet, and node-exporter.
$ErrorActionPreference = 'Stop'
$remote = '192.168.10.0/24'

$rules = @(
  @{ Name = 'Homelab Desktop WSL SSH'; Port = 2222 },
  @{ Name = 'Homelab Desktop kubelet'; Port = 10250 },
  @{ Name = 'Homelab Desktop node-exporter'; Port = 9100 },
  @{ Name = 'Homelab Desktop DCGM exporter'; Port = 9400 }
)

foreach ($rule in $rules) {
  $existing = netsh advfirewall firewall show rule name="$($rule.Name)" 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Rule already exists: $($rule.Name)"
    continue
  }
  netsh advfirewall firewall add rule `
    name="$($rule.Name)" `
    dir=in action=allow protocol=TCP `
    localport=$rule.Port remoteip=$remote profile=any | Out-Null
  Write-Host "Added: $($rule.Name) TCP $($rule.Port) from $remote"
}

Write-Host 'Done. Test from blackpearl: ssh -p 2222 -i ~/.ssh/homelab s4il0r@192.168.10.31 hostname'
