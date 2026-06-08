#Requires -Version 5.1
<#
.SYNOPSIS
  Push Obsevia demo deploy credentials from local .env / Vault to GitHub Actions secrets.
  NEVER prints secret values — only secret names and repo targets.

.PARAMETER Repo
  GitHub repo slug under obsevia-compliance (e.g. QROMA-DEMO, DUCAH, DP-DEMO).

.PARAMETER DryRun
  Print gh secret set commands without executing.

.PARAMETER EnvFile
  Path to Obsevia/.env (default: sibling Obsevia/.env from homelab-k3s).
#>
param(
  [Parameter(Mandatory)]
  [ValidateSet("QROMA-DEMO", "DUCAH", "DP-DEMO")]
  [string] $Repo,

  [switch] $DryRun,
  [string] $EnvFile = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent
if (-not $EnvFile) {
  $EnvFile = Join-Path (Split-Path $RepoRoot -Parent) "Obsevia\.env"
}

function Read-DotEnv([string] $Path) {
  $vars = @{}
  if (-not (Test-Path $Path)) { return $vars }
  foreach ($line in Get-Content $Path) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -match '^\s*([^=]+?)\s*=\s*(.*)$') {
      $vars[$Matches[1].Trim()] = $Matches[2].Trim().Trim('"').Trim("'")
    }
  }
  return $vars
}

$env = Read-DotEnv $EnvFile
if ($env.Count -eq 0) { throw "No vars in $EnvFile" }

$shiphookUrls = @{
  "QROMA-DEMO" = "https://shiphook.obsevia.d3bu7.com/deploy/staging/qroma"
  "DUCAH"      = "https://shiphook.obsevia.d3bu7.com/deploy/staging/ducah"
  "DP-DEMO"    = "https://shiphook.obsevia.d3bu7.com/deploy/staging/dp"
}

$mapping = [ordered]@{
  NEXT_PUBLIC_SUPABASE_URL       = @("NEXT_PUBLIC_SUPABASE_URL", "VPS1_SUPABASE_URL")
  NEXT_PUBLIC_SUPABASE_ANON_KEY  = @("NEXT_PUBLIC_SUPABASE_ANON_KEY", "VPS1_SUPABASE_ANON_KEY")
  SUPABASE_SERVICE_ROLE_KEY    = @("SUPABASE_SERVICE_ROLE_KEY", "VPS1_SUPABASE_SERVICE_ROLE_KEY")
  SUPABASE_TEST_EMAIL          = @("SUPABASE_TEST_EMAIL")
  SUPABASE_TEST_PASSWORD       = @("SUPABASE_TEST_PASSWORD")
  GH_TOKEN                     = @("GH_TOKEN", "GITHUB_TOKEN")
  VPS1_HOST                    = @("VPS1_HOST")
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh -and -not $DryRun) { throw "gh CLI not found - install GitHub CLI" }

$target = "obsevia-compliance/$Repo"
Write-Host "Syncing GitHub Actions secrets for $target from $EnvFile"
Write-Host "(values are never printed)"
Write-Host ""

# Fixed URL per repo
Write-Host "  SHIPHOOK_STAGING_URL"
if ($DryRun) {
  Write-Host ('    gh secret set SHIPHOOK_STAGING_URL --repo ' + $target + ' --body [url]')
} else {
  $shiphookUrls[$Repo] | gh secret set SHIPHOOK_STAGING_URL --repo $target
}

foreach ($secretName in $mapping.Keys) {
  $val = $null
  foreach ($src in $mapping[$secretName]) {
    if ($env.ContainsKey($src) -and $env[$src]) { $val = $env[$src]; break }
  }
  if (-not $val) {
    Write-Host "  skip $secretName (no source in .env)"
    continue
  }
  Write-Host "  $secretName"
  if ($DryRun) {
    Write-Host ('    gh secret set ' + $secretName + ' --repo ' + $target + ' --body [redacted]')
  } else {
    $val | gh secret set $secretName --repo $target
  }
}

Write-Host ""
Write-Host "Manual secrets (not in Obsevia/.env):"
Write-Host "  SHIPHOOK_STAGING_SECRET  - from blackpearl ~/staging/shiphook-server/.shiphook.staging.secret"
Write-Host "  VPS1_SSH_PRIVATE_KEY     - OpenSSH private key for root@VPS1 (e.g. obsevia_deploy)"
Write-Host ""
Write-Host "Vault optional: seed KV then re-run after exporting to .env"
Write-Host "  VAULT_ADDR=https://vault.klaut.pro  vault kv get secret/saas/obsevia/staging/"
