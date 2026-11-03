param(
  [Parameter(Mandatory=$true)][string]$Profile,
  [Parameter(Mandatory=$true)][string]$Credentials,
  [string]$Distro = 'Ubuntu-24.04',
  [int]$Port = 2079
)
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run PowerShell as Administrator.' }
$Profile = (Resolve-Path -LiteralPath $Profile).Path
$Credentials = (Resolve-Path -LiteralPath $Credentials).Path
$wsl = "$env:windir\System32\wsl.exe"
$linuxProfile = (& $wsl -d $Distro -u root -- wslpath -a $Profile).Trim()
$linuxCreds = (& $wsl -d $Distro -u root -- wslpath -a $Credentials).Trim()
$linuxRepo = (& $wsl -d $Distro -u root -- wslpath -a $PSScriptRoot).Trim()
if (($linuxProfile + $linuxCreds + $linuxRepo) -match "'") { throw 'Paths containing an apostrophe are not supported.' }
& $wsl -d $Distro -u root -- bash "$linuxRepo/install-linux.sh" "$linuxRepo" "$linuxProfile" "$linuxCreds" "$Port"
if ($LASTEXITCODE -ne 0) { throw 'WSL installation failed. Check the output above.' }
$state = Join-Path $env:LOCALAPPDATA 'OpenVPNLocalProxy'
New-Item -ItemType Directory -Force $state | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'start.ps1') $state -Force
@{Distro=$Distro;Port=$Port} | ConvertTo-Json | Set-Content (Join-Path $state 'settings.json') -Encoding UTF8
$action=New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$state\start.ps1`""
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask -TaskName 'OpenVPN Local Proxy' -Action $action -Trigger $trigger -RunLevel Highest -Force | Out-Null
& (Join-Path $state 'start.ps1')
