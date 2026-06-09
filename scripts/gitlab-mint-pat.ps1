# Mint GitLab PAT via kubectl + gitlab-rails (Windows / PowerShell).
param(
  [string]$PatName = $(if ($env:PAT_NAME) { $env:PAT_NAME } else { "dev-workstation" }),
  [string]$PatScopes = $(if ($env:PAT_SCOPES) { $env:PAT_SCOPES } else { "api,read_api,read_repository,write_repository" }),
  [string]$OutFile = $(if ($env:OUT_FILE) { $env:OUT_FILE } else { Join-Path (Join-Path $PSScriptRoot "..") ".gitlab-token.local" }),
  [string]$KubeConfig = $(if ($env:KUBECONFIG) { $env:KUBECONFIG } else { Join-Path (Join-Path $env:USERPROFILE ".kube") "config-homelab" }),
  [string]$Namespace = $(if ($env:GITLAB_NAMESPACE) { $env:GITLAB_NAMESPACE } else { "gitlab" }),
  [string]$Pod = $(if ($env:GITLAB_POD) { $env:GITLAB_POD } else { "gitlab-0" })
)

$ErrorActionPreference = "Stop"
$env:KUBECONFIG = $KubeConfig
$outPod = "/tmp/gitlab-mint-pat-out"
$scriptPod = "/tmp/gitlab-mint-pat.rb"

$ruby = @"
user = User.find_by(username: 'root')
user = User.admins.first if user.nil?
abort('no admin user') unless user
name = '$PatName'
scopes = '$PatScopes'.split(',').map(&:strip)
available = Gitlab::Auth.all_available_scopes.map(&:to_s)
scopes = scopes & available
abort('no valid scopes') if scopes.empty?
out_file = '$outPod'
user.personal_access_tokens.where(name: name).find_each { |t| t.revoke! unless t.revoked? }
token = PersonalAccessToken.new(user: user, name: name, scopes: scopes, expires_at: 1.year.from_now)
token.save!
File.write(out_file, token.token)
"@

$tmpRuby = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmpRuby -Value $ruby -NoNewline
try {
  cmd /c "kubectl cp `"$tmpRuby`" ${Namespace}/${Pod}:${scriptPod} 2>nul" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "kubectl cp failed" }
  cmd /c "kubectl exec -n $Namespace $Pod -- gitlab-rails runner `"load '$scriptPod'`" 2>nul" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "gitlab-rails runner failed" }
  $token = (cmd /c "kubectl exec -n $Namespace $Pod -- cat $outPod 2>nul").Trim()
  cmd /c "kubectl exec -n $Namespace $Pod -- rm -f $outPod $scriptPod 2>nul" | Out-Null
} finally {
  Remove-Item -Force $tmpRuby -ErrorAction SilentlyContinue
}

if (-not $token) { throw "empty token from pod $outPod" }

$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

if ($OutFile -match '\.env(\.local)?$') {
  if (-not (Test-Path $OutFile)) {
    Set-Content -Path $OutFile -Value "GITLAB_TOKEN=$token"
  } else {
    $lines = Get-Content $OutFile
    $found = $false
    $newLines = foreach ($line in $lines) {
      if ($line -match '^GITLAB_TOKEN=') { $found = $true; "GITLAB_TOKEN=$token" } else { $line }
    }
    if (-not $found) { $newLines += "GITLAB_TOKEN=$token" }
    Set-Content -Path $OutFile -Value $newLines
  }
} else {
  Set-Content -Path $OutFile -Value "GITLAB_TOKEN=$token"
}

$suffix = $token.Substring([Math]::Max(0, $token.Length - 4))
Write-Host "OK: minted PAT name=$PatName -> $OutFile (suffix ...$suffix)"
