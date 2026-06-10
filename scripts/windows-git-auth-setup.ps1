# One-time Windows git auth: store GitLab PAT in Credential Manager (no popups).
# GitHub uses gh CLI (already configured if `gh auth status` is OK).
param(
  [string]$EnvFile = $(if ($env:ENV_FILE) { $env:ENV_FILE } else { Join-Path (Join-Path $PSScriptRoot "../..") ".env.local" }),
  [string]$TokenFile = $(if ($env:GITLAB_TOKEN_FILE) { $env:GITLAB_TOKEN_FILE } else { Join-Path (Join-Path $PSScriptRoot "..") ".gitlab-token.local" })
)

$ErrorActionPreference = "Stop"

function Read-GitLabToken {
  foreach ($path in @($EnvFile, $TokenFile)) {
    if (-not (Test-Path $path)) { continue }
    $line = Get-Content $path | Where-Object { $_ -match '^GITLAB_TOKEN=' } | Select-Object -First 1
    if ($line) { return ($line -replace '^GITLAB_TOKEN=', '').Trim() }
  }
  return $null
}

function Approve-GitCred([string]$Token, [string]$Protocol, [string]$CredHost) {
  @"
protocol=$Protocol
host=$CredHost
username=oauth2
password=$Token

"@ | git credential approve
  Write-Host "Stored credential: ${Protocol}://${CredHost}"
}

$token = Read-GitLabToken
if (-not $token) {
  Write-Host "No GITLAB_TOKEN in $EnvFile or $TokenFile"
  Write-Host "Mint one first: cd homelab-k3s && OUT_FILE=../.env.local npm run gitlab:auth"
  exit 1
}

# Self-hosted GitLab: generic provider (not GCM OAuth). GitHub stays on gh.
git config --global credential.helper manager
git config --global credential.https://gitlab.lilangverse.xyz.helper manager
git config --global credential.https://gitlab.lilangverse.xyz.provider generic

$nodeportHosts = @(
  "192.168.10.32:30481",
  "192.168.10.33:30481",
  "127.0.0.1:18080",
  "127.0.0.1:30481"
)
foreach ($h in $nodeportHosts) {
  git config --global "credential.http://${h}.helper" manager
  git config --global "credential.http://${h}.provider" generic
  Approve-GitCred $token "http" $h
}

Approve-GitCred $token "https" "gitlab.lilangverse.xyz"

# Verify non-interactive (agents / CI-style)
$env:GIT_TERMINAL_PROMPT = "0"
$env:GCM_INTERACTIVE = "never"
$probe = git ls-remote "https://gitlab.lilangverse.xyz/li-langverse/lic.git" HEAD 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "Probe failed: $probe"
  exit 1
}

Write-Host "OK: GitLab HTTPS auth stored in Windows Credential Manager."
Write-Host "GitHub: run 'gh auth status' — uses gh auth git-credential (no GCM popup)."
