# Parallel 18-asset curl probe for GitLab sign_in via edge (strict 18/18 gate).
param(
    [string]$HostName = $(if ($env:GITLAB_HOST) { $env:GITLAB_HOST } else { 'gitlab.lilangverse.xyz' }),
    [string]$EdgeIp = $(if ($env:EDGE_IP) { $env:EDGE_IP } else { '192.168.10.33' })
)

$ErrorActionPreference = 'Continue'
$HtmlPath = Join-Path $env:TEMP 'gitlab_sign_in.html'
$curlBase = @(
    '--ssl-no-revoke',
    '--http1.1',
    '--no-keepalive',
    '--no-sessionid',
    '-H', 'Connection: close',
    '--resolve', "${HostName}:443:${EdgeIp}",
    '--max-time', '180'
)

& curl.exe -sk @curlBase -o $HtmlPath "https://${HostName}/users/sign_in"
$html = Get-Content $HtmlPath -Raw
$paths = [regex]::Matches($html, '(?:href|src)="(/assets/[^"]+\.(?:css|js))"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

Write-Host "assets=$($paths.Count)"

$jobs = @()
foreach ($path in $paths) {
    $jobs += Start-Job -ScriptBlock {
        param($HostName, $EdgeIp, $path)
        $hdrFile = Join-Path $env:TEMP "probe_hdr_$([guid]::NewGuid().ToString('N')).txt"
        $outFile = Join-Path $env:TEMP "probe_body_$([guid]::NewGuid().ToString('N')).bin"
        $meta = curl.exe -sk --ssl-no-revoke --http1.1 --no-keepalive --no-sessionid `
            -H 'Connection: close' --resolve "${HostName}:443:${EdgeIp}" --max-time 180 `
            -D $hdrFile -o $outFile -w '%{http_code} %{size_download}' "https://${HostName}${path}" 2>$null
        $parts = $meta -split ' ', 2
        $code = $parts[0]; $dl = if ($parts.Length -gt 1) { $parts[1] } else { '0' }
        $clenLine = Select-String -Path $hdrFile -Pattern '^content-length:' -CaseSensitive:$false | Select-Object -Last 1
        $clen = if ($clenLine) { ($clenLine.Line -replace 'content-length:\s*', '').Trim() } else { '' }
        $bytes = if (Test-Path $outFile) { [System.IO.File]::ReadAllBytes($outFile) } else { @() }
        $first = if ($bytes.Length -ge 1) { '{0:x2}' -f $bytes[0] } else { 'x' }
        Remove-Item $hdrFile, $outFile -ErrorAction SilentlyContinue
        [pscustomobject]@{ code = $code; dl = $dl; clen = $clen; first = $first; path = $path }
    } -ArgumentList $HostName, $EdgeIp, $path
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

$pass = 0
foreach ($r in $results) {
    $ok = ($r.code -eq '200') -and $r.clen -and ($r.dl -eq $r.clen) -and ($r.first -ne '3c')
    if ($ok) { $pass++ } else {
        Write-Host "FAIL $($r.code) dl=$($r.dl) clen=$($r.clen) first=$($r.first) $($r.path)"
    }
}

Write-Host "RESULT parallel-edge: ${pass}/$($paths.Count)"
if ($pass -ne $paths.Count -or $paths.Count -lt 1) { exit 1 }
