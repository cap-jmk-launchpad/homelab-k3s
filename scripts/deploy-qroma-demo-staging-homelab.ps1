#Requires -Version 5.1
param(
  [switch] $SkipBuild,
  [switch] $SkipImageImport,
  [ValidateSet("engine", "blackpearl")]
  [string] $Target = "engine",
  [string] $QromaRoot = "C:\Users\Julian\Documents\Programming\Obsevia\QROMA-DEMO",
  [string] $SshKey = "C:\Users\Julian\Documents\Programming\beelink-cleanup\homelab",
  [string] $Kubeconfig = "$env:USERPROFILE\.kube\config-homelab"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ImageName = "obsevia-qroma-demo-staging:latest"
$ImportHost = if ($Target -eq "engine") { "engine" } else { "192.168.10.41" }
$SshUser = "s4il0r"
$bun = "$env:USERPROFILE\.bun\bin\bun.exe"
if (-not (Test-Path $bun)) { $bun = "bun" }

function Get-EnvFromDotLocal([string] $Path, [string] $Name) {
  if (-not (Test-Path $Path)) { return $null }
  foreach ($line in Get-Content $Path) {
    if ($line -match "^\s*#") { continue }
    if ($line -match "^\s*$Name\s*=\s*(.+)\s*$") {
      return $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
  return $null
}

$envLocal = Join-Path $QromaRoot ".env.local"
$supabaseUrl = Get-EnvFromDotLocal $envLocal "NEXT_PUBLIC_SUPABASE_URL"
$supabaseAnon = Get-EnvFromDotLocal $envLocal "NEXT_PUBLIC_SUPABASE_ANON_KEY"
if (-not $supabaseUrl) { $supabaseUrl = "https://supabase.obsevia.com" }
if (-not $supabaseAnon) { $supabaseAnon = "changeme-anon-key" }

$secretPath = Join-Path $RepoRoot "k8s\staging\qroma-demo\secret.yaml"
if (-not (Test-Path $secretPath)) {
  Copy-Item (Join-Path $RepoRoot "k8s\staging\qroma-demo\secret.example.yaml") $secretPath
  Write-Host "Created k8s/staging/qroma-demo/secret.yaml — edit anon key if needed."
}

if (-not $SkipBuild) {
  Write-Host "Building $ImageName from $QromaRoot..."
  Set-Location $QromaRoot
  & $bun run build
  docker build -t $ImageName `
    --build-arg "NEXT_PUBLIC_SUPABASE_URL=$supabaseUrl" `
    --build-arg "NEXT_PUBLIC_SUPABASE_ANON_KEY=$supabaseAnon" `
    --build-arg "NEXT_PUBLIC_APP_URL=https://qroma.obsevia.com" `
    -f Dockerfile .
  docker tag $ImageName docker.io/library/obsevia-qroma-demo-staging:latest
}

if (-not $SkipImageImport) {
  if (-not (Test-Path $SshKey)) { throw "SSH key not found: $SshKey" }
  $tar = Join-Path $env:TEMP "obsevia-qroma-demo-staging.tar"
  Write-Host "Importing image to ${SshUser}@${ImportHost}..."
  docker save -o $tar docker.io/library/obsevia-qroma-demo-staging:latest
  scp -i $SshKey $tar "${SshUser}@${ImportHost}:/tmp/obsevia-qroma-demo-staging.tar"
  $importCmd = "sudo k3s ctr images import /tmp/obsevia-qroma-demo-staging.tar; sudo k3s ctr images tag localhost/obsevia-qroma-demo-staging:latest docker.io/library/obsevia-qroma-demo-staging:latest 2>/dev/null; rm -f /tmp/obsevia-qroma-demo-staging.tar"
  ssh -i $SshKey "${SshUser}@${ImportHost}" $importCmd
  Remove-Item -Force $tar -ErrorAction SilentlyContinue
}

if (Test-Path $Kubeconfig) {
  $env:KUBECONFIG = $Kubeconfig
  Set-Location $RepoRoot
  kubectl apply -f $secretPath
  kubectl apply -k (Join-Path $RepoRoot "k8s\staging\qroma-demo\base")
  kubectl -n obsevia-qroma-staging rollout status deployment/obsevia-qroma-demo --timeout=180s
  kubectl -n obsevia-qroma-staging get pods -o wide
} else {
  Write-Warning "Kubeconfig not found at $Kubeconfig"
}

Write-Host ""
Write-Host "Homelab staging URLs (after edge apply on blackpearl):"
Write-Host "  http://qroma.homelab.lan/dashboard"
Write-Host "  http://qroma.obsevia.com/dashboard  (DNS -> edge host)"
Write-Host "  http://192.168.10.33:30584/dashboard"
Write-Host ""
Write-Host "Edge: apply homelab.httpd.toml on blackpearl via edge-lis-apply.sh"
