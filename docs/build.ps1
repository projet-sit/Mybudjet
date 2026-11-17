<#
.SYNOPSIS
  Régénère toute la documentation générée de MyBudget (diagrammes, site API, exports PDF/DOCX).

.DESCRIPTION
  Idempotent : peut être relancé autant de fois que nécessaire.
  Étapes :
    1) Vérifie les outils (node, npm, npx, pandoc, Chrome si disponible)
    2) Installe les dépendances de docs/ si absentes
    3) Génère PNG + SVG de chaque diagramme Mermaid (docs/diagrams)
    4) Valide l'OpenAPI (redocly lint) puis construit docs/api/index.html
    5) Génère export/dossier-de-conception.docx (pandoc, TOC + numérotation)
    6) Génère export/dossier-de-conception.pdf et export/guide-utilisateur.pdf (md-to-pdf)

.EXEMPLE
  .\docs\build.ps1
#>
[CmdletBinding()]
param(
  [switch]$SkipDiagrams,
  [switch]$SkipApi,
  [switch]$SkipExports
)
$ErrorActionPreference = 'Stop'
$docs = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $docs
$export = Join-Path $docs 'export'
$failed = @()

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    ✔ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "    ✘ $msg" -ForegroundColor Red; $script:failed += $msg }

Step 'Vérification des outils'
foreach ($tool in 'node', 'npm', 'npx', 'pandoc') {
  $cmd = Get-Command $tool -ErrorAction SilentlyContinue
  if ($cmd) { Ok "$tool : $($cmd.Source)" } else { Fail "$tool est introuvable. Installez-le puis relancez." }
}
if ($failed.Count -gt 0) { Write-Host "`nBuild interrompu : outils manquants." -ForegroundColor Red; exit 1 }

# Chrome (pour mermaid-cli / md-to-pdf sans téléchargement de Chromium)
$chromeCandidates = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($chrome) {
  $env:PUPPETEER_EXECUTABLE_PATH = $chrome
  Ok "Chrome détecté : $chrome"
  # Config puppeteer pour mermaid-cli (fichier généré, non versionné)
  $cfg = @{ executablePath = $chrome; args = @('--no-sandbox', '--disable-dev-shm-usage') } | ConvertTo-Json
  Set-Content -Path (Join-Path $docs 'puppeteer-config.json') -Value $cfg -Encoding UTF8
} else {
  Warn 'Google Chrome introuvable : mmdc / md-to-pdf utiliseront le navigateur téléchargé par puppeteer si présent.'
}

Step 'Dépendances de la documentation'
Push-Location $docs
try {
  if (-not (Test-Path (Join-Path $docs 'node_modules'))) {
    $env:PUPPETEER_SKIP_DOWNLOAD = '1'
    npm install
  }
  Ok 'Dépendances présentes'
} catch {
  Write-Host "    ✘ Échec des dépendances : $_" -ForegroundColor Red
  Pop-Location
  exit 1
}

if (-not $SkipDiagrams) {
  Step 'Diagrammes Mermaid (PNG + SVG)'
  Get-ChildItem (Join-Path $docs 'diagrams\*.mmd') | ForEach-Object {
    $base = $_.BaseName
    $png = Join-Path $docs "diagrams\$base.png"
    $svg = Join-Path $docs "diagrams\$base.svg"
    $cfgPath = Join-Path $docs 'puppeteer-config.json'
    $mmdcArgs = @('-i', $_.FullName, '-o', $png, '-b', 'transparent')
    if (Test-Path $cfgPath) { $mmdcArgs = @('-p', $cfgPath) + $mmdcArgs }
    & npx mmdc @mmdcArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "diagramme $base (png)" } else { Ok "$base.png" }
    $svgArgs = @('-i', $_.FullName, '-o', $svg, '-b', 'transparent')
    if (Test-Path $cfgPath) { $svgArgs = @('-p', $cfgPath) + $svgArgs }
    & npx mmdc @svgArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "diagramme $base (svg)" } else { Ok "$base.svg" }
  }
}

if (-not $SkipApi) {
  Step 'OpenAPI — validation Redocly'
  Push-Location $docs
  try {
    & npx redocly lint 'api/openapi.yaml'
    if ($LASTEXITCODE -ne 0) { Fail 'redocly lint a trouvé des erreurs' } else { Ok 'OpenAPI valide (0 erreur)' }
    & npx redocly build-docs 'api/openapi.yaml' -o 'api/index.html'
    if ($LASTEXITCODE -ne 0) { Fail 'redocly build-docs' } else { Ok 'api/index.html régénéré' }
  } finally { Pop-Location }
}

if (-not $SkipExports) {
  Step 'Exports (Word + PDF)'
  New-Item -ItemType Directory -Force $export | Out-Null

  Step '  Word : export/dossier-de-conception.docx'
  & pandoc (Join-Path $docs 'dossier-de-conception.md') `
    -o (Join-Path $export 'dossier-de-conception.docx') `
    --toc --number-sections -V lang=fr --from 'markdown+pipe_tables' "--resource-path=$docs"
  if ($LASTEXITCODE -ne 0) { Fail 'pandoc docx' } else {
    $size = (Get-Item (Join-Path $export 'dossier-de-conception.docx')).Length
    if ($size -lt 10KB) { Fail 'DOCX suspicieusement petit' } else { Ok "DOCX généré ($([math]::Round($size/1KB)) Ko)" }
  }

  Step '  PDF : export/dossier-de-conception.pdf'
  Push-Location $docs
  try {
    & npx md-to-pdf 'dossier-de-conception.md' --stylesheet 'pdf.css' --launch-options '{"args":["--no-sandbox","--disable-dev-shm-usage"]}' | Out-Null
    if (Test-Path (Join-Path $docs 'dossier-de-conception.pdf')) {
      Move-Item -Force (Join-Path $docs 'dossier-de-conception.pdf') (Join-Path $export 'dossier-de-conception.pdf')
      Ok 'PDF dossier généré'
    } else { Fail 'md-to-pdf (dossier)' }
  } finally { Pop-Location }

  Step '  PDF : export/guide-utilisateur.pdf'
  Push-Location (Join-Path $docs 'guide')
  try {
    & npx md-to-pdf 'guide-utilisateur.md' --stylesheet '../pdf.css' --launch-options '{"args":["--no-sandbox","--disable-dev-shm-usage"]}' | Out-Null
    if (Test-Path 'guide-utilisateur.pdf') {
      Move-Item -Force 'guide-utilisateur.pdf' (Join-Path $export 'guide-utilisateur.pdf')
      Ok 'PDF guide généré'
    } else { Fail 'md-to-pdf (guide)' }
  } finally { Pop-Location }
}

Pop-Location
Step 'Résumé'
if ($failed.Count -gt 0) {
  Write-Host "ÉCHEC : $($failed.Count) étape(s) en erreur :" -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}
Get-ChildItem $export | ForEach-Object { Write-Host ("  {0}  ({1} Ko)" -f $_.Name, [math]::Round($_.Length / 1KB)) }
Write-Host "`nBuild documentation OK." -ForegroundColor Green
