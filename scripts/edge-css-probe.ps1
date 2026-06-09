# GitLab edge CSS probe for Windows workstations (Schannel curl).
# LAN split-DNS: resolve gitlab.lilangverse.xyz -> 192.168.10.33 (hosts or CoreDNS).
param(
    [string]$HostName = 'gitlab.lilangverse.xyz',
    [string]$EdgeIp = '192.168.10.33',
    [int]$ExpectedBytes = 835437,
    [int]$Runs = 10,
    [int]$SleepSec = 3
)

$ErrorActionPreference = 'Continue'
$css = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    $html = & curl.exe -sk --ssl-no-revoke --resolve "${HostName}:443:${EdgeIp}" --max-time 60 "https://${HostName}/users/sign_in" 2>$null
    if ($html -match '(/assets/application-[a-f0-9]+\.css)') {
        $css = $Matches[1]
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $css) {
    Write-Error "Could not discover CSS path from sign_in"
    exit 2
}

$curlBase = @(
    '--ssl-no-revoke',
    '--resolve', "${HostName}:443:${EdgeIp}",
    '--no-sessionid',
    '--no-keepalive',
    '--http1.1',
    '--max-time', '120'
)

$pass = 0
for ($i = 1; $i -le $Runs; $i++) {
    $sign = & curl.exe -sk @curlBase -o $null -w '%{http_code}' "https://${HostName}/users/sign_in"
    $size = & curl.exe -sk @curlBase -o $null -w '%{size_download}' "https://${HostName}${css}"
    $ok = ($sign -eq '200' -or $sign -eq '302') -and ($size -eq "$ExpectedBytes")
    if ($ok) { $pass++ }
    $status = if ($ok) { 'PASS' } else { 'FAIL' }
    Write-Host "run ${i}: ${status} sign=${sign} css=${size}"
    if ($i -lt $Runs) { Start-Sleep -Seconds $SleepSec }
}
Write-Host "RESULT workstation: ${pass}/${Runs} (css=${css})"
if ($pass -lt $Runs) {
    Write-Host "Note: Schannel curl often truncates large TLS bodies despite HTTP 200 and correct Content-Length."
    Write-Host "Use browser or blackpearl edge-css-probe.sh for acceptance; edge is OK when blackpearl LAN is 10/10."
}
exit $(if ($pass -eq $Runs) { 0 } else { 1 })
