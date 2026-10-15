$ErrorActionPreference = 'Stop'

function Get-EnvKey {
    $candidate = $env:OPENCODE_API_KEY
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = [Environment]::GetEnvironmentVariable('OPENCODE_API_KEY', 'User')
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    return $candidate.Trim()
}

function Test-JevKey([string] $Key) {
    $payload = @{
        model = 'jev-1.13-free'
        state = 'Installer smoke test. Water freezes at 0 degrees Celsius under standard atmospheric pressure.'
        questions = @{
            installer_check = @{
                type = 'noul'
                instructions = 'Is the statement generally true under standard atmospheric pressure?'
            }
        }
    } | ConvertTo-Json -Depth 8

    try {
        $reply = Invoke-RestMethod -Uri 'https://opencode.ai/zen/v1/systemone' `
            -Method Post `
            -Headers @{ Authorization = "Bearer $Key" } `
            -ContentType 'application/json' `
            -Body $payload `
            -TimeoutSec 30
        if (-not $reply.answers.installer_check) {
            throw 'Jev yanıtında beklenen answers alanı yok.'
        }
        Write-Host "Jev API testi başarılı. Model: $($reply.model); input tokens: $($reply.usage.input_tokens); output tokens: $($reply.usage.output_tokens)" -ForegroundColor Green
        return $true
    } catch {
        $statusCode = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            throw 'OpenCode Zen anahtarı reddedildi (401/403). Anahtarı kontrol et.'
        }
        if ($statusCode -eq 429) {
            throw 'Jev ücretsiz kullanım limiti/hız sınırı dolmuş olabilir (429). Anahtar bu denemede kaydedilmedi. Daha sonra tekrar dene.'
        }
        if ($statusCode -eq 402) {
            throw 'API ücretsiz erişim isteğini reddetti (402). Zen hesabı ve Jev Free erişimini kontrol et. Anahtar bu denemede kaydedilmedi.'
        }
        if ($statusCode) {
            throw "Jev API testi HTTP $statusCode hatasıyla başarısız oldu. Anahtar kaydedilmedi."
        }
        throw "Jev API testi başarısız oldu: $($_.Exception.Message). Anahtar kaydedilmedi."
    }
}

Write-Host 'Jev MCP Bridge kurulumu başlıyor.' -ForegroundColor Cyan

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) { throw 'Node.js bulunamadı. Node.js 20 veya üzeri kur ve PowerShell’i yeniden aç.' }
$nodeVersionText = (& node --version).Trim()
$nodeMajor = 0
if ($nodeVersionText -match '^v?(\d+)') { $nodeMajor = [int]$Matches[1] }
if ($nodeMajor -lt 20) { throw "Node.js 20 veya üzeri gerekli. Bulunan sürüm: $nodeVersionText" }

$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) { throw 'npm bulunamadı. Node.js kurulumunu kontrol et.' }
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) { throw 'Claude Code CLI bulunamadı. Önce claude komutunun PowerShell’de çalıştığını doğrula.' }

$key = Get-EnvKey
$enteredNewKey = $false
if ([string]::IsNullOrWhiteSpace($key)) {
    $secureKey = Read-Host 'OpenCode Zen API anahtarını gir (ekranda gösterilmez)' -AsSecureString
    if ($secureKey.Length -lt 10) { throw 'Girilen API anahtarı çok kısa görünüyor; kurulum durduruldu.' }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secureKey.Dispose() }
    $enteredNewKey = $true
}

# Verify access before persisting a newly entered key. This uses one small Jev Free API request.
Test-JevKey -Key $key | Out-Null

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetRoot = Join-Path $HOME '.claude-mcp\jev-bridge'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $targetRoot 'src') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $targetRoot 'scripts') -Force | Out-Null

foreach ($file in @('package.json', 'README.md')) {
    $sourceFile = Join-Path $sourceRoot $file
    if (Test-Path $sourceFile) { Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $targetRoot $file) -Force }
}
Copy-Item -Path (Join-Path $sourceRoot 'src\*') -Destination (Join-Path $targetRoot 'src') -Recurse -Force
Copy-Item -Path (Join-Path $sourceRoot 'scripts\*') -Destination (Join-Path $targetRoot 'scripts') -Recurse -Force

Write-Host 'MCP bağımlılıkları kuruluyor...' -ForegroundColor Cyan
Push-Location $targetRoot
try {
    & npm install --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw "npm install başarısız oldu (exit code $LASTEXITCODE)." }
    & node --check (Join-Path $targetRoot 'src\index.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Node.js söz dizimi kontrolü başarısız oldu.' }
} finally {
    Pop-Location
}

# Save to the current user's environment only after the real API request has succeeded.
# Environment variables are stored by Windows in the current user's profile, not in source code.
[Environment]::SetEnvironmentVariable('OPENCODE_API_KEY', $key, 'User')
$env:OPENCODE_API_KEY = $key

# If a same-name user MCP server exists, ask before replacing only that entry.
$listOutput = (& claude mcp list 2>&1 | Out-String)
if ($listOutput -match '(?im)^\s*jev-bridge\b') {
    $answer = Read-Host 'Claude Code’da jev-bridge adlı MCP kaydı zaten var. Yalnızca bu kaydı yenisiyle değiştireyim mi? (y/N)'
    if ($answer -match '^(y|yes|e|evet)$') {
        & claude mcp remove jev-bridge --scope user
        if ($LASTEXITCODE -ne 0) { throw 'Mevcut jev-bridge kaydı kaldırılamadı; kayıt değiştirilmedi.' }
    } else {
        throw 'Kurulum, mevcut jev-bridge MCP kaydını korumak için durduruldu. Dosyalar kuruldu ancak MCP kaydı eklenmedi.'
    }
}

$nodePath = (Get-Command node).Source
$entryPath = Join-Path $targetRoot 'src\index.mjs'
Write-Host 'Claude Code’a kullanıcı kapsamlı MCP sunucusu kaydediliyor...' -ForegroundColor Cyan
& claude mcp add --scope user jev-bridge -- $nodePath $entryPath
if ($LASTEXITCODE -ne 0) {
    throw 'Dosyalar kuruldu ancak Claude Code MCP kaydı eklenemedi. README.md içindeki manuel kayıt komutunu kullan.'
}

Write-Host ''
Write-Host 'Kurulum tamamlandı.' -ForegroundColor Green
Write-Host "Dosyalar: $targetRoot"
Write-Host 'Doğrulama: claude mcp get jev-bridge --scope user'
Write-Host 'Claude Code’u tamamen kapatıp yeniden aç, ardından /mcp komutuyla jev-bridge araçlarını kontrol et.'
Write-Host 'Gerçek MCP araç çağrısını Claude Code içinde jev_assess ve jev_code_triage ile test et.'
Write-Host 'API anahtarı konsola yazdırılmadı, kaynak koduna eklenmedi ve ücretli modele otomatik geçiş yapılandırılmadı.'
