#Requires -Version 5.1
<#
.SYNOPSIS
  Build DUCAH (DUCA-DEMO) staging image, import to engine, apply k8s staging manifests.

.PARAMETER SkipBuild
  Skip podman build (reuse local image).

.PARAMETER SkipImageImport
  Skip save/scp/ctr import (image already on engine).

.PARAMETER Target
  k3s node to schedule pods and import image: engine (default) or blackpearl.
#>
param(
  [switch] $SkipBuild,
  [switch] $SkipImageImport,
  [ValidateSet("engine", "blackpearl")]
  [string] $Target = "engine",
  [string] $DucaDemoRoot = "C:\Users\Julian\Documents\Programming\Obsevia\DUCA-DEMO",
  [string] $SshKey = "C:\Users\Julian\Documents\Programming\beelink-cleanup\homelab",
  [string] $Kubeconfig = "$env:USERPROFILE\.kube\config-homelab"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ImageName = "obsevia-duca-demo-staging:latest"
$ImportHost = if ($Target -eq "engine") { "engine" } else { "192.168.10.41" }
$SshUser = "s4il0r"

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

$envLocal = Join-Path $DucaDemoRoot ".env.local"
$supabaseUrl = Get-EnvFromDotLocal $envLocal "NEXT_PUBLIC_SUPABASE_URL"
$supabaseAnon = Get-EnvFromDotLocal $envLocal "NEXT_PUBLIC_SUPABASE_ANON_KEY"
if (-not $supabaseUrl) { $supabaseUrl = "http://ducah.homelab.lan" }
if (-not $supabaseAnon) { $supabaseAnon = "changeme-anon-key" }
$supabaseUpstream = Get-EnvFromDotLocal $envLocal "SUPABASE_UPSTREAM_URL"
if (-not $supabaseUpstream) { $supabaseUpstream = "http://192.168.10.41:30000" }

$secretPath = Join-Path $RepoRoot "k8s\staging\duca-demo\secret.yaml"
if (-not (Test-Path $secretPath)) {
  Copy-Item (Join-Path $RepoRoot "k8s\staging\duca-demo\secret.example.yaml") $secretPath
  Write-Host "Created k8s/staging/duca-demo/secret.yaml - edit anon key if needed."
}

if (-not $SkipBuild) {
  Write-Host "Building $ImageName from $DucaDemoRoot..."
  Set-Location $DucaDemoRoot
  podman build -t $ImageName `
    --build-arg "NEXT_PUBLIC_SUPABASE_URL=$supabaseUrl" `
    --build-arg "NEXT_PUBLIC_SUPABASE_ANON_KEY=$supabaseAnon" `
    --build-arg "SUPABASE_UPSTREAM_URL=$supabaseUpstream" `
    -f Dockerfile .
  podman tag $ImageName docker.io/library/obsevia-duca-demo-staging:latest
}

if (-not $SkipImageImport) {
  if (-not (Test-Path $SshKey)) { throw "SSH key not found: $SshKey" }
  $tar = Join-Path $env:TEMP "obsevia-duca-demo-staging.tar"
  Write-Host "Importing image to ${SshUser}@${ImportHost}..."
  podman save -o $tar docker.io/library/obsevia-duca-demo-staging:latest
  scp -i $SshKey $tar "${SshUser}@${ImportHost}:/tmp/obsevia-duca-demo-staging.tar"
  $importCmd = "sudo k3s ctr images import /tmp/obsevia-duca-demo-staging.tar; sudo k3s ctr images tag localhost/obsevia-duca-demo-staging:latest docker.io/library/obsevia-duca-demo-staging:latest 2>/dev/null; rm -f /tmp/obsevia-duca-demo-staging.tar"
  ssh -i $SshKey "${SshUser}@${ImportHost}" $importCmd
  Remove-Item -Force $tar -ErrorAction SilentlyContinue
}

if (-not (Test-Path $Kubeconfig)) {
  Write-Warning "Kubeconfig not found at $Kubeconfig"
} else {
  $env:KUBECONFIG = $Kubeconfig
  Set-Location $RepoRoot
  kubectl apply -f $secretPath
  kubectl apply -k (Join-Path $RepoRoot "k8s\staging\duca-demo\overlays\engine")
  kubectl -n obsevia-ducah-staging rollout status deployment/obsevia-duca-demo --timeout=180s
  kubectl -n obsevia-ducah-staging get pods -o wide
}

Write-Host ""
Write-Host "Homelab staging URLs (after edge apply on blackpearl):"
Write-Host "  http://ducah.homelab.lan/login"
Write-Host "  http://ducah.obsevia.d3bu7.com/login  (hosts/DNS -> 192.168.10.33)"
Write-Host "  http://192.168.10.33:30583/login"
Write-Host ""
Write-Host "Edge: apply homelab.httpd.toml on blackpearl via edge-lis-apply.sh"
Write-Host ""
