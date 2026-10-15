$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath $PSScriptRoot

function Invoke-Checked([string] $Command, [string[]] $Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Komut başarısız oldu (exit code $LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

$requiredFiles = @('README.md', 'package.json', 'install.ps1', 'src/index.mjs', 'scripts/test-api.mjs', '.gitignore')
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file))) {
        throw "Gerekli dosya bulunamadı: $file"
    }
}

foreach ($commandName in @('git', 'gh', 'node', 'npm')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "'$commandName' komutu bulunamadı. Git, Node.js/npm ve GitHub CLI kurulumunu kontrol et. GitHub CLI: https://cli.github.com/"
    }
}

Write-Host 'GitHub CLI kimlik doğrulaması kontrol ediliyor...' -ForegroundColor Cyan
Invoke-Checked 'gh' @('auth', 'status')
$login = (& gh api user --jq .login | Out-String).Trim()
$userId = (& gh api user --jq .id | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($login) -or [string]::IsNullOrWhiteSpace($userId)) {
    throw 'GitHub hesabı doğrulanamadı. Önce gh auth login çalıştır.'
}
Write-Host "GitHub hesabı: $login" -ForegroundColor Green

$repoName = Read-Host 'Yeni depo adı [jev-mcp-bridge]'
if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = 'jev-mcp-bridge' }
if ($repoName -notmatch '^[A-Za-z0-9_.-]{1,100}$') {
    throw 'Depo adı yalnızca harf, rakam, nokta, alt çizgi ve tire içerebilir.'
}

Write-Host 'Depo görünürlüğü: [P]rivate (varsayılan) / [U]blic' -ForegroundColor Cyan
$visibilityInput = (Read-Host 'Seçim [P]').Trim().ToLowerInvariant()
$visibility = if ($visibilityInput -in @('u', 'public', 'pub')) { 'public' } else { 'private' }
if ($visibility -eq 'public') {
    Write-Warning 'Depo herkese açık olacak. Şu an LICENSE dosyası yok; public yayımdan önce bir lisans seçmen önerilir.'
    $confirmPublic = Read-Host 'Herkese açık repo oluşturmak için PUBLIC yaz'
    if ($confirmPublic -cne 'PUBLIC') { throw 'Public yayın iptal edildi.' }
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git'))) {
    Invoke-Checked 'git' @('init', '-b', 'main')
}
$remoteNames = @(& git remote)
if ($LASTEXITCODE -ne 0) {
    throw 'Git remote list could not be read.'
}
if ($remoteNames -contains 'origin') {
    $existingRemote = (& git remote get-url origin | Out-String).Trim()
    throw "This folder already has an origin remote: $existingRemote. Stopped to avoid pushing to the wrong repository."
}

Write-Host 'Paket bağımlılıkları kilitleniyor; lifecycle scriptleri çalıştırılmayacak...' -ForegroundColor Cyan
Invoke-Checked 'npm' @('install', '--save-exact', '--ignore-scripts', '--no-audit', '--no-fund')
Invoke-Checked 'npm' @('run', 'check')

Write-Host 'Git dosyaları hazırlanıyor...' -ForegroundColor Cyan
Invoke-Checked 'git' @('add', '-A')
$stagedFiles = @(& git diff --cached --name-only)
$forbidden = @($stagedFiles | Where-Object {
    $_ -match '(^|/)node_modules(/|$)' -or
    $_ -match '(^|/)\.npmrc$' -or
    ($_ -match '(^|/)\.env($|\.)' -and $_ -ne '.env.example') -or
    $_ -match '(^|/)secrets?(/|$)' -or
    $_ -match '\.(pem|key|p12|pfx)$' -or
    $_ -match '(^|/)(npm-debug|yarn-debug|pnpm-debug).*\.log$'
})
if ($forbidden.Count -gt 0) {
    throw "Gizli/üretilmiş olabilecek dosyalar staged durumda. Hiçbiri push edilmedi. Önce bunları kaldır: $($forbidden -join ', ')"
}

# Scan only staged added/changed text; never print the matched line or its contents.
$stagedDiff = (& git diff --cached --no-ext-diff --unified=0 | Out-String)
$secretPatterns = @(
    '(?i)\bsk-[A-Za-z0-9_-]{20,}\b',
    '(?i)\boc_[A-Za-z0-9_-]{20,}\b',
    '(?i)\bgh[pousr]_[A-Za-z0-9]{20,}\b',
    '(?i)\bgithub_pat_[A-Za-z0-9_]{20,}\b'
)
foreach ($pattern in $secretPatterns) {
    if ($stagedDiff -match $pattern) {
        throw 'Staged değişikliklerde anahtara benzeyen bir değer bulundu. İçerik gizlilik nedeniyle gösterilmedi; push yapılmadı.'
    }
}

$gitUserName = (& git config user.name 2>$null | Out-String).Trim()
$gitUserEmail = (& git config user.email 2>$null | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($gitUserName)) {
    Invoke-Checked 'git' @('config', '--local', 'user.name', $login)
}
if ([string]::IsNullOrWhiteSpace($gitUserEmail)) {
    Invoke-Checked 'git' @('config', '--local', 'user.email', "$userId+$login@users.noreply.github.com")
}

$hasHead = $true
& $env:ComSpec /d /c 'git rev-parse --verify HEAD >NUL 2>&1'
if ($LASTEXITCODE -ne 0) { $hasHead = $false }
$hasStagedChanges = $false
& git diff --cached --quiet
if ($LASTEXITCODE -eq 1) { $hasStagedChanges = $true } elseif ($LASTEXITCODE -gt 1) { throw 'Git staged değişiklikleri kontrol edilemedi.' }
if ($hasStagedChanges) {
    Invoke-Checked 'git' @('commit', '-m', 'chore: initial Jev MCP bridge release')
} elseif (-not $hasHead) {
    throw 'Commit edilecek dosya bulunamadı.'
} else {
    Write-Host 'Staged değişiklik yok; mevcut commit kullanılacak.' -ForegroundColor Yellow
}

$repoFullName = "$login/$repoName"
Write-Host "GitHub deposu oluşturuluyor: $repoFullName ($visibility)" -ForegroundColor Cyan
$visibilityFlag = if ($visibility -eq 'public') { '--public' } else { '--private' }
Invoke-Checked 'gh' @('repo', 'create', $repoFullName, $visibilityFlag, '--source', '.', '--remote', 'origin', '--push')
Write-Host ''
Write-Host 'Yayın tamamlandı.' -ForegroundColor Green
Write-Host "Repo: https://github.com/$repoFullName"
Write-Host 'Kurulu MCP, ayrı bir klasörde bulunduğu için bu kaynak repo push işlemi kurulu Jev MCP kaydını değiştirmez.'
