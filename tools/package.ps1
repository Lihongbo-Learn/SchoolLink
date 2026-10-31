param(
  [switch]$SkipBuild,
  [string]$Flutter = 'flutter',
  [string]$Dart = 'dart',
  [string]$Iscc = $env:ISCC_PATH
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'apps\app'
$dist = Join-Path $root 'dist'
$winDir = Join-Path $dist 'SchoolLink-Windows'
$hubDir = Join-Path $dist 'SchoolLinkHub'
$linuxDir = Join-Path $dist 'SchoolLinkHub-linux'

if (-not $Iscc) {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 7\ISCC.exe'
  )
  $Iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc) {
  throw 'ISCC.exe not found. Install Inno Setup 6 and set ISCC_PATH if needed.'
}

if (-not $SkipBuild) {
  Push-Location $app
  & $Flutter pub get
  & $Flutter build web --release --no-web-resources-cdn
  & $Flutter build windows --release
  & $Flutter build apk --release
  Pop-Location
}

if (Test-Path $winDir) { Remove-Item $winDir -Recurse -Force }
New-Item -ItemType Directory -Path $winDir | Out-Null
Copy-Item -Path (Join-Path $app 'build\windows\x64\runner\Release\*') -Destination $winDir -Recurse
Copy-Item -Path (Join-Path $app 'build\web') -Destination (Join-Path $winDir 'web') -Recurse

if (Test-Path $hubDir) { Remove-Item $hubDir -Recurse -Force }
New-Item -ItemType Directory -Path $hubDir | Out-Null
Push-Location (Join-Path $root 'packages\hub')
& $Dart compile exe bin/server.dart -o (Join-Path $hubDir 'SchoolLinkHub.exe')
Pop-Location
Copy-Item -Path (Join-Path $app 'build\web') -Destination (Join-Path $hubDir 'web') -Recurse
@'
@echo off
cd /d "%~dp0"
SchoolLinkHub.exe --port 8421 --data "%LOCALAPPDATA%\SchoolLinkHub" --web-root "%~dp0web"
pause
'@ | Set-Content -Encoding ascii (Join-Path $hubDir 'start-hub.bat')
New-Item -ItemType Directory -Path (Join-Path $winDir 'hub') | Out-Null
Copy-Item -Path (Join-Path $hubDir '*') -Destination (Join-Path $winDir 'hub') -Recurse

Copy-Item -Path (Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk') -Destination (Join-Path $dist 'SchoolLink-Android.apk') -Force
Copy-Item -Path (Join-Path $root 'README.md') -Destination (Join-Path $winDir 'README.md') -Force
Copy-Item -Path (Join-Path $root 'tools\enable-firewall.ps1') -Destination (Join-Path $winDir 'enable-firewall.ps1') -Force
Copy-Item -Path (Join-Path $root 'tools\enable-firewall.ps1') -Destination (Join-Path $hubDir 'enable-firewall.ps1') -Force

# Linux Hub bundle: one-command installer + web + pure-Dart source fallback.
if (Test-Path $linuxDir) { Remove-Item $linuxDir -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $linuxDir 'source\packages') -Force | Out-Null
Copy-Item -Path (Join-Path $root 'installer\install-hub-linux.sh') -Destination (Join-Path $linuxDir 'install.sh')
Copy-Item -Path (Join-Path $app 'build\web') -Destination (Join-Path $linuxDir 'web') -Recurse
Copy-Item -Path (Join-Path $root 'packages\protocol') -Destination (Join-Path $linuxDir 'source\packages\protocol') -Recurse
Copy-Item -Path (Join-Path $root 'packages\hub') -Destination (Join-Path $linuxDir 'source\packages\hub') -Recurse
Get-ChildItem -Path (Join-Path $linuxDir 'source') -Recurse -Directory -Filter '.dart_tool' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem -Path (Join-Path $linuxDir 'source') -Recurse -Directory -Filter 'build' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Copy-Item -Path (Join-Path $root 'README.md') -Destination (Join-Path $linuxDir 'README.md') -Force
$linuxTar = Join-Path $dist 'SchoolLinkHub-linux.tar.gz'
if (Test-Path $linuxTar) { Remove-Item $linuxTar -Force }
$tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
& $tarExe -czf $linuxTar -C $dist 'SchoolLinkHub-linux'

& $Iscc (Join-Path $root 'installer\SchoolLink.iss')

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $dist 'SchoolLink-Windows.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($winDir, $zip)
$hubZip = Join-Path $dist 'SchoolLinkHub.zip'
if (Test-Path $hubZip) { Remove-Item $hubZip -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($hubDir, $hubZip)

$checksumTargets = Get-ChildItem $dist -File |
  Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
  Sort-Object Name
$lines = foreach ($file in $checksumTargets) {
  $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $($file.Name)"
}
$checksumText = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText(
  (Join-Path $dist 'SHA256SUMS.txt'),
  $checksumText,
  (New-Object System.Text.UTF8Encoding($false))
)
Write-Host "Packaging complete: $dist"
