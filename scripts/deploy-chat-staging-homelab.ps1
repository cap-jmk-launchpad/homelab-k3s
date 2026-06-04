#Requires -Version 5.1
<#
.SYNOPSIS
  Build chatbot-frontend staging image, import into k3s on the schedule target node, apply homelab manifests.

.PARAMETER Target
  Kubernetes schedule + image import node: engine (default) or blackpearl.

.PARAMETER ChatFrontendRoot
  Path to chatbot-frontend repo (default: Obsevia/obsevia-compliance/chatbot-frontend).

.PARAMETER SkipBuild
  Skip podman/docker build.

.PARAMETER SkipImageImport
  Skip save/scp/ctr import.

.PARAMETER SkipEdge
  Do not print edge apply reminder.
#>
param(
  [ValidateSet("engine", "blackpearl")]
  [string] $Target = "engine",
  [string] $ChatFrontendRoot = "C:\Users\Julian\Documents\Programming\Obsevia\obsevia-compliance\chatbot-frontend",
  [switch] $SkipBuild,
  [switch] $SkipImageImport,
  [switch] $SkipEdge,
  [string] $SshUser = "s4il0r",
  [string] $SshKey = (Join-Path $PSScriptRoot "..\homelab"),
  [string] $ImageName = "obsevia-frontend-staging:latest",
  [string] $Kubeconfig = "$env:USERPROFILE\.kube\config-homelab"
)

$ErrorActionPreference = "Stop"
$BeelinkRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ChatK8sRoot = Join-Path $BeelinkRoot "k8s\staging\chat-frontend"
$K8sDir = Join-Path $ChatK8sRoot "overlays\$Target"
$NodeHosts = @{
  engine     = "engine"          # 192.168.10.32 k3s agent
  blackpearl = "192.168.10.41"   # SSH; k3s internal 192.168.10.33
}
$ImportHost = $NodeHosts[$Target]
if (-not $ImportHost) { throw "Unknown target: $Target" }
$SecretPath = Join-Path $ChatK8sRoot "secret.yaml"
$SecretExample = Join-Path $ChatK8sRoot "secret.example.yaml"

function Get-EnvValue([string] $File, [string] $Name) {
  if (-not (Test-Path $File)) { return $null }
  foreach ($line in Get-Content $File) {
    if ($line -match "^\s*#") { continue }
    if ($line -match "^\s*$Name\s*=\s*(.+)\s*$") {
      return $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
  return $null
}

if (-not (Test-Path $ChatFrontendRoot)) {
  throw "chatbot-frontend not found at $ChatFrontendRoot - set -ChatFrontendRoot"
}

$envStaging = Join-Path $ChatFrontendRoot ".env.staging"
$envExample = Join-Path $ChatFrontendRoot ".env.staging.example"

if (-not (Test-Path $SecretPath)) {
  if (Test-Path $envStaging) {
    Write-Host "Creating secret.yaml from .env.staging..."
    $lines = @(
      "apiVersion: v1",
      "kind: Secret",
      "metadata:",
      "  name: obsevia-chat-frontend-secrets",
      "  namespace: obsevia-chat-staging",
      "  labels:",
      "    app: obsevia-chat-frontend",
      "type: Opaque",
      "stringData:"
    )
    foreach ($key in @(
        "NEXT_PUBLIC_SUPABASE_URL",
        "NEXT_PUBLIC_SUPABASE_ANON_KEY",
        "NEXT_PUBLIC_API_URL",
        "SUPABASE_SERVICE_ROLE_KEY"
      )) {
      $val = Get-EnvValue $envStaging $key
      if ($val) { $lines += "  ${key}: $val" }
    }
    if ($lines.Count -le 8) {
      Copy-Item $SecretExample $SecretPath
      Write-Warning "secret.yaml created from example - fill Supabase/API keys before apply."
    } else {
      $lines | Set-Content -Encoding utf8 $SecretPath
    }
  } else {
    Copy-Item $SecretExample $SecretPath
    Write-Warning "Created secret.yaml from example - copy .env.staging or edit keys."
  }
}

$envFile = if (Test-Path $envStaging) { $envStaging } else { $envExample }
$siteUrl = Get-EnvValue $envFile "NEXT_PUBLIC_SITE_URL"
if (-not $siteUrl) { $siteUrl = "https://chat.obsevia.d3bu7.com" }
$deployEnv = Get-EnvValue $envFile "NEXT_PUBLIC_DEPLOY_ENV"
if (-not $deployEnv) { $deployEnv = "staging" }
$supabaseUrl = Get-EnvValue $envFile "NEXT_PUBLIC_SUPABASE_URL"
$supabaseAnon = Get-EnvValue $envFile "NEXT_PUBLIC_SUPABASE_ANON_KEY"
$apiUrl = Get-EnvValue $envFile "NEXT_PUBLIC_API_URL"
$serviceRole = Get-EnvValue $envFile "SUPABASE_SERVICE_ROLE_KEY"

if (-not $supabaseUrl -or -not $supabaseAnon) {
  Write-Warning "NEXT_PUBLIC_SUPABASE_* missing in $envFile - build may fail or auth will not work."
}

if (-not $SkipBuild) {
  $buildArgs = @(
    "--build-arg", "NEXT_PUBLIC_SITE_URL=$siteUrl",
    "--build-arg", "NEXT_PUBLIC_DEPLOY_ENV=$deployEnv",
    "--build-arg", "NEXT_PUBLIC_SUPABASE_URL=$supabaseUrl",
    "--build-arg", "NEXT_PUBLIC_SUPABASE_ANON_KEY=$supabaseAnon",
    "--build-arg", "NEXT_PUBLIC_API_URL=$apiUrl",
    "--build-arg", "SUPABASE_SERVICE_ROLE_KEY=$serviceRole"
  )
  Write-Host "Building $ImageName in $ChatFrontendRoot ..."
  Push-Location $ChatFrontendRoot
  try {
    if (Get-Command podman -ErrorAction SilentlyContinue) {
      podman build -t $ImageName @buildArgs -f Dockerfile .
      podman tag $ImageName docker.io/library/obsevia-frontend-staging:latest
    } elseif (Get-Command docker -ErrorAction SilentlyContinue) {
      docker build -t $ImageName @buildArgs -f Dockerfile .
      docker tag $ImageName docker.io/library/obsevia-frontend-staging:latest
    } else {
      throw "Install podman or docker for image build."
    }
  } finally {
    Pop-Location
  }
}

if (-not $SkipImageImport) {
  if (-not (Test-Path $SshKey)) {
    throw "SSH key not found: $SshKey"
  }
  $tar = Join-Path $env:TEMP "obsevia-frontend-staging.tar"
  Write-Host "Saving image to $tar ..."
  if (Get-Command podman -ErrorAction SilentlyContinue) {
    podman save -o $tar docker.io/library/obsevia-frontend-staging:latest
  } else {
    docker save -o $tar docker.io/library/obsevia-frontend-staging:latest
  }
  Write-Host "Importing image on $Target ($ImportHost) ..."
  scp -i $SshKey $tar "${SshUser}@${ImportHost}:/tmp/obsevia-frontend-staging.tar"
  $importCmd = 'sudo k3s ctr images import /tmp/obsevia-frontend-staging.tar; ' +
    'sudo k3s ctr images tag localhost/obsevia-frontend-staging:latest docker.io/library/obsevia-frontend-staging:latest 2>/dev/null; ' +
    'rm -f /tmp/obsevia-frontend-staging.tar'
  ssh -i $SshKey "${SshUser}@${ImportHost}" $importCmd
  Remove-Item -Force $tar -ErrorAction SilentlyContinue
}

if (-not (Test-Path $Kubeconfig)) {
  Write-Warning "Kubeconfig missing at $Kubeconfig - apply manifests manually."
} else {
  $env:KUBECONFIG = $Kubeconfig
  Write-Host "Applying Kubernetes manifests..."
  kubectl apply -f $SecretPath
  kubectl apply -k $K8sDir
  kubectl -n obsevia-chat-staging rollout status deployment/obsevia-chat-frontend --timeout=180s
  kubectl -n obsevia-chat-staging get pods,svc
}

if (-not $SkipEdge) {
  Write-Host ""
  Write-Host "Edge (one-time on blackpearl after homelab.httpd.toml includes chat routes):"
  Write-Host "  cd ~/staging/beelink-cleanup; bash scripts/edge-lis-validate.sh; sudo bash scripts/edge-lis-apply.sh"
  Write-Host ""
  Write-Host "LAN URL:  http://chat.homelab.lan/login"
  Write-Host "Staging:  http://chat.obsevia.d3bu7.com/login  (hosts/DNS -> 192.168.10.33)"
  Write-Host "NodePort: http://192.168.10.33:30581/login  (pods on $Target)"
  Write-Host "Engine debug: http://192.168.10.32:30581/login"
  Write-Host ""
}
