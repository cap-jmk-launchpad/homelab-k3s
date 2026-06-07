#Requires -Version 5.1
# Parse homelab .env (KEY=value). Safe when .env is missing.
function Read-HomelabDotEnvFile {
    param([Parameter(Mandatory)][string]$Path)

    $vars = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $vars }

    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw -replace '^\xEF\xBB\xBF', ''
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*([^=]+?)\s*=\s*(.*)$') {
            $vars[$Matches[1].Trim()] = $Matches[2].Trim().Trim('"').Trim("'")
        }
    }
    return $vars
}

function Get-HomelabDotEnv {
    param(
        [string]$BeelinkRoot = "",
        [string]$RepoRoot = ""
    )

    if (-not $BeelinkRoot) {
        $candidate = Split-Path $PSScriptRoot -Parent
        if (Test-Path -LiteralPath (Join-Path $candidate "homelab-k3s")) {
            $BeelinkRoot = $candidate
        }
    }
    if (-not $RepoRoot) {
        if ($BeelinkRoot -and (Test-Path -LiteralPath (Join-Path $BeelinkRoot "homelab-k3s"))) {
            $RepoRoot = Join-Path $BeelinkRoot "homelab-k3s"
        } else {
            $RepoRoot = Split-Path $PSScriptRoot -Parent
        }
    }

    $merged = @{}
    foreach ($path in @(
            (Join-Path $BeelinkRoot ".env"),
            (Join-Path $RepoRoot ".env")
        )) {
        if (-not $path) { continue }
        foreach ($entry in (Read-HomelabDotEnvFile -Path $path).GetEnumerator()) {
            if ($entry.Value) { $merged[$entry.Key] = $entry.Value }
        }
    }
    return $merged
}

function Get-HomelabEnvPath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$Env = $null,
        [string]$Default = ""
    )

    if (-not $Env) { $Env = Get-HomelabDotEnv }
    if ($Env.ContainsKey($Name) -and $Env[$Name]) { return $Env[$Name] }
    return $Default
}
