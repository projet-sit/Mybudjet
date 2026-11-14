# Rebuild de l'APK arm64 de production (MYBUDGET).
# 1) Définit GOOGLE_SERVER_CLIENT_ID / API_BASE_URL dans mobile/.env
# 2) Lance ce script : build release + obfuscation + split arm64
# 3) Copie l'APK dans les destinations de livraison.

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "=== flutter pub get ===" -ForegroundColor Cyan
flutter pub get

Write-Host "=== flutter analyze ===" -ForegroundColor Cyan
flutter analyze

Write-Host "=== build apk release arm64 (obfuscate) ===" -ForegroundColor Cyan
flutter build apk --release --flavor direct --split-per-abi `
  --obfuscate --split-debug-info=build/debug-info

$src = "$root\build\app\outputs\flutter-apk\app-arm64-v8a-direct-release.apk"
$assets = "$root\..\flutter-apk\app-arm64-v8a-direct-release-obfuscated.apk"
$rootDeliver = "$root\..\app-arm64-v8a-direct-release-obfuscated.apk"
Copy-Item $src $assets -Force
Copy-Item $src $rootDeliver -Force

Write-Host ""
Write-Host "Livré :" -ForegroundColor Green
Write-Host "  $assets"
Write-Host "  $rootDeliver"
