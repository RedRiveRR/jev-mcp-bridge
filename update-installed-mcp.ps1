$ErrorActionPreference = 'Stop'
$sourceRoot = $PSScriptRoot
$targetRoot = Join-Path $HOME '.claude-mcp\jev-bridge'

if (-not (Test-Path (Join-Path $targetRoot 'src\index.mjs'))) {
  throw "Mevcut Jev MCP kurulumu bulunamadı: $targetRoot. Önce install.ps1 çalıştır."
}
if (-not (Test-Path (Join-Path $sourceRoot 'src\index.mjs'))) {
  throw 'Repo içindeki src\index.mjs bulunamadı; betiği proje kökünden çalıştır.'
}

Write-Host 'MCP sunucusu kodu kopyalanıyor...' -ForegroundColor Cyan
Copy-Item -LiteralPath (Join-Path $sourceRoot 'src\index.mjs') -Destination (Join-Path $targetRoot 'src\index.mjs') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $targetRoot 'scripts') | Out-Null
Copy-Item -Path (Join-Path $sourceRoot 'scripts\*') -Destination (Join-Path $targetRoot 'scripts') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'package.json') -Destination (Join-Path $targetRoot 'package.json') -Force

Push-Location $targetRoot
try {
  & npm install --no-audit --no-fund --ignore-scripts
  if ($LASTEXITCODE -ne 0) { throw "npm install başarısız oldu (exit code $LASTEXITCODE)." }
  & npm run check
  if ($LASTEXITCODE -ne 0) { throw 'Sözdizimi kontrolleri başarısız oldu.' }
} finally { Pop-Location }

Write-Host 'MCP kodu güncellendi. Claude Code’u tamamen kapatıp yeniden aç; /mcp içinde clef_assess ve clef_code_triage araçlarını doğrula.' -ForegroundColor Green
Write-Host 'Cloudflare kimlik bilgileri henüz yoksa önce configure-clef.ps1 çalıştır.'
