param(
  [string]$Flutter = 'flutter'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

Push-Location (Join-Path $root 'apps\app')
& $Flutter pub get
& $Flutter build web --release --no-web-resources-cdn
& $Flutter build windows --release
& $Flutter build apk --debug
Pop-Location
Write-Host 'Builds complete.'
