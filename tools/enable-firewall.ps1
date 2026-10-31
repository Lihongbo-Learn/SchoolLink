# Run as Administrator.
# Removes Windows Firewall block rules for SchoolLink and allows the LAN ports
# used by the app, scoped to the local subnet only.

param(
    [string[]]$ExtraPrograms = @()
)

$ErrorActionPreference = 'SilentlyContinue'
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: This script must be run as Administrator.'
    exit 1
}

$log = Join-Path $env:TEMP 'SchoolLink-firewall.log'

# 1) Remove Windows-created inbound BLOCK rules for SchoolLink.
$blockRules = Get-NetFirewallRule -Direction Inbound -Action Block -ErrorAction SilentlyContinue
foreach ($rule in $blockRules) {
    $app = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    $program = $app.Program
    if (($rule.DisplayName -match 'schoollink') -or ($program -match 'SchoolLink')) {
        Remove-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
    }
}

# 2) Remove old SchoolLink rules created by earlier versions of this script.
Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -like 'SchoolLink *' -or
        $_.DisplayName -like '校联*' -or
        $_.Group -eq 'SchoolLink'
    } |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

# 3) Add LAN-only allow rules (both Public and Private network profiles).
$portRules = @(
    @{ Name = 'SchoolLink Hub HTTP/WS 8421'; Protocol = 'TCP'; Port = '8421' },
    @{ Name = 'SchoolLink Hub Discovery 8421'; Protocol = 'UDP'; Port = '8421' },
    @{ Name = 'SchoolLink Peer 8422'; Protocol = 'TCP'; Port = '8422' },
    @{ Name = 'SchoolLink Peer Discovery 8424'; Protocol = 'UDP'; Port = '8424' }
)
foreach ($rule in $portRules) {
    New-NetFirewallRule `
        -DisplayName $rule.Name `
        -Group 'SchoolLink' `
        -Direction Inbound `
        -Action Allow `
        -Protocol $rule.Protocol `
        -LocalPort $rule.Port `
        -RemoteAddress LocalSubnet `
        -Profile Public,Private `
        -Enabled True | Out-Null
}

# 4) Allow known executables explicitly. Paths are resolved relative to this
#    repository and the default per-user install location.
$repoRoot = Split-Path $PSScriptRoot -Parent
$programs = @(
    (Join-Path $repoRoot 'dist\SchoolLinkHub\SchoolLinkHub.exe'),
    (Join-Path $repoRoot 'dist\SchoolLink-Windows\hub\SchoolLinkHub.exe'),
    (Join-Path $repoRoot 'dist\SchoolLink-Windows\school_link.exe'),
    (Join-Path $repoRoot 'apps\app\build\windows\x64\runner\Release\school_link.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\SchoolLink\school_link.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\SchoolLink\hub\SchoolLinkHub.exe')
) + $ExtraPrograms
foreach ($program in $programs | Select-Object -Unique) {
    if (Test-Path $program) {
        $name = 'SchoolLink Program ' + (Split-Path $program -Leaf)
        New-NetFirewallRule `
            -DisplayName $name `
            -Group 'SchoolLink' `
            -Direction Inbound `
            -Action Allow `
            -Program $program `
            -RemoteAddress LocalSubnet `
            -Profile Public,Private `
            -Enabled True | Out-Null
    }
}

# 5) Report the resulting rules and LAN URLs.
$summary = Get-NetFirewallRule -Group 'SchoolLink' -ErrorAction SilentlyContinue |
    Select-Object DisplayName, Enabled, Profile, Direction, Action
$summary | Format-Table -AutoSize | Out-String | Tee-Object -FilePath $log
Write-Host ''
Write-Host 'SchoolLink firewall rules updated. Test from another device on the same LAN:'
$ips = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
    Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
    ForEach-Object { $_.IPv4Address.IPAddress }
foreach ($ip in $ips | Select-Object -Unique) {
    Write-Host "  http://${ip}:8421/"
}
