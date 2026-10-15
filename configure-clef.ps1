$ErrorActionPreference = 'Stop'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'Node.js bulunamadı. Node.js 20 veya üzeri kur ve PowerShell’i yeniden aç.' }

$accountId = Read-Host 'Cloudflare Account ID (32 karakterlik kimlik; gizli değil)'
if ($accountId -notmatch '^[a-fA-F0-9]{32}$') { throw 'Account ID biçimi geçersiz. Cloudflare dashboard hesabındaki 32 karakterlik Account ID değerini kullan.' }

$secureToken = Read-Host 'Cloudflare API Token gir (ekranda gösterilmez; Account > Workers AI > Read yetkili)' -AsSecureString
if ($secureToken.Length -lt 20) { $secureToken.Dispose(); throw 'API token çok kısa görünüyor; kurulum durduruldu.' }
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
try { $apiToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secureToken.Dispose() }

$env:CLOUDFLARE_ACCOUNT_ID = $accountId
$env:CLOUDFLARE_API_TOKEN = $apiToken

Write-Host 'Clef-Flash erişimi küçük bir API isteğiyle test ediliyor. Bu, Workers AI ücretsiz Neuron tahsisinden az miktarda kullanır.' -ForegroundColor Cyan
& node (Join-Path $PSScriptRoot 'scripts\test-clef-api.mjs')
if ($LASTEXITCODE -ne 0) {
    Remove-Item Env:CLOUDFLARE_API_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue
    throw 'Clef-Flash testi başarısız. Kimlik bilgileri Windows kullanıcı ortamına kaydedilmedi.'
}

[Environment]::SetEnvironmentVariable('CLOUDFLARE_ACCOUNT_ID', $accountId, 'User')
[Environment]::SetEnvironmentVariable('CLOUDFLARE_API_TOKEN', $apiToken, 'User')
Write-Host 'Cloudflare kimlik bilgileri test sonrası Windows kullanıcı ortamına kaydedildi.' -ForegroundColor Green
Write-Host 'Bu token özel bir secrets vault değildir. Kaynak koda veya GitHub deposuna ekleme.'
Write-Host 'Mevcut PowerShell penceresinde environment değerleri set edildi. Claude Code süreçleri bu değerleri almak için tamamen kapatılıp yeniden açılmalıdır.'
