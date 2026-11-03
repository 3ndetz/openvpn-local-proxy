$ErrorActionPreference = 'Stop'
$config = Get-Content (Join-Path $PSScriptRoot 'settings.json') -Raw | ConvertFrom-Json
$wsl = "$env:windir\System32\wsl.exe"
& $wsl -d $config.Distro -u root -- systemctl start openvpn-local-proxy.service
if ($LASTEXITCODE -ne 0) { throw 'Could not start VPN service.' }
$ip = (& $wsl -d $config.Distro -u root -- sh -c "hostname -I" | Out-String).Trim().Split(' ',[StringSplitOptions]::RemoveEmptyEntries)[0]
if ($ip -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Could not determine WSL IPv4 address.' }
& "$env:windir\System32\netsh.exe" interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$($config.Port) | Out-Null
& "$env:windir\System32\netsh.exe" interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=$($config.Port) connectaddress=$ip connectport=$($config.Port)
if ($LASTEXITCODE -ne 0) { throw 'Could not configure Windows port forwarding.' }
Write-Host "Proxy: 127.0.0.1:$($config.Port)"
