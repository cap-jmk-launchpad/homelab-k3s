# Parallel 18-asset GitLab sign_in probe (browser load pattern).
# Pass: every asset HTTP 200, downloaded bytes == Content-Length, body not HTML error.
param(
    [string]$Resolve = $(if ($env:EDGE_PROBE_RESOLVE) { $env:EDGE_PROBE_RESOLVE } else { 'gitlab.lilangverse.xyz:443:192.168.10.33' }),
    [string]$Label = $(if ($env:EDGE_PROBE_LABEL) { $env:EDGE_PROBE_LABEL } else { 'parallel-18' })
)

$ErrorActionPreference = 'Continue'
$parts = $Resolve -split ':', 3
if ($parts.Count -lt 3) {
    Write-Error "EDGE_PROBE_RESOLVE must be host:port:ip (got '$Resolve')"
    exit 1
}
$HostName = $parts[0]
$Port = $parts[1]
$EdgeIp = $parts[2]
$Origin = if ($Port -eq '443') { "https://${HostName}" } else { "https://${HostName}:${Port}" }

$HtmlPath = Join-Path $env:TEMP 'edge_parallel_sign_in.html'
$curlBase = @(
    '--ssl-no-revoke',
    '--http1.1',
    '--no-keepalive',
    '--no-sessionid',
    '-H', 'Connection: close',
    '--resolve', "${HostName}:${Port}:${EdgeIp}",
    '--max-time', '30'
)

& curl.exe -sk @curlBase -o $HtmlPath "${Origin}/users/sign_in"
$html = Get-Content $HtmlPath -Raw -ErrorAction SilentlyContinue
$paths = [regex]::Matches($html, '(?:href|src)="(/assets/[^"]+\.(?:css|js))"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

$n = $paths.Count
if ($n -ne 18) {
    Write-Host "FAIL ${Label}: expected 18 assets, got ${n}"
    exit 1
}

$jobs = @()
foreach ($path in $paths) {
    $jobs += Start-Job -ScriptBlock {
        param($HostName, $Port, $EdgeIp, $Origin, $path)
        $hdrFile = Join-Path $env:TEMP "probe_hdr_$([guid]::NewGuid().ToString('N')).txt"
        $outFile = Join-Path $env:TEMP "probe_body_$([guid]::NewGuid().ToString('N')).bin"
        $meta = curl.exe -sk --ssl-no-revoke --http1.1 --no-keepalive --no-sessionid `
            -H 'Connection: close' --resolve "${HostName}:${Port}:${EdgeIp}" --max-time 180 `
            -D $hdrFile -o $outFile -w '%{http_code} %{size_download}' "${Origin}${path}" 2>$null
        $metaParts = $meta -split ' ', 2
        $code = $metaParts[0]
        $wire = if ($metaParts.Length -gt 1) { $metaParts[1] } else { '0' }
        $clenLine = Select-String -Path $hdrFile -Pattern '^content-length:' -CaseSensitive:$false | Select-Object -Last 1
        $clen = if ($clenLine) { ($clenLine.Line -replace 'content-length:\s*', '').Trim() } else { '' }
        $bytes = if (Test-Path $outFile) { [System.IO.File]::ReadAllBytes($outFile) } else { @() }
        $first = if ($bytes.Length -ge 1) { '{0:x2}' -f $bytes[0] } else { 'x' }
        Remove-Item $hdrFile, $outFile -ErrorAction SilentlyContinue
        [pscustomobject]@{ code = $code; wire = $wire; clen = $clen; first = $first; path = $path }
    } -ArgumentList $HostName, $Port, $EdgeIp, $Origin, $path
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force

$pass = 0
$fail = 0
foreach ($r in $results) {
    $ok = ($r.code -eq '200') -and $r.clen -and ($r.wire -eq $r.clen) -and ($r.first -ne '3c')
    if ($ok) { $pass++ } else {
        $fail++
        Write-Host "FAIL $($r.code) wire=$($r.wire) clen=$($r.clen) first=$($r.first) $($r.path)"
    }
}

Write-Host "RESULT ${Label}: ${pass}/${n}"
if ($fail -ne 0) { exit 1 }
