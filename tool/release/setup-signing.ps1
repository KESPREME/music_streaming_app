<#
.SYNOPSIS
  One-time setup of the signing key that CI uses, and the GitHub secrets for it.

.DESCRIPTION
  Android installs an update only over an app signed with the SAME key. So the key
  CI signs with is the identity of the app. Choose how you get it:

    -UseDebugKey   Reuse this computer's debug keystore (~/.android/debug.keystore).
                   Every copy you already installed from `flutter run` / a local
                   build is signed with it, so those copies update in place and
                   nobody has to reinstall. Fine for a personal/beta app; do not
                   ship publicly with a key that is also on a dev machine.

    -Generate      Create a fresh release keystore. Phones with an older,
                   differently signed copy must uninstall once before the first
                   OTA update. Keep the file and the passwords somewhere safe:
                   lose them and nobody can ever update again.

  Then it uploads the four secrets CI reads, with the GitHub CLI (gh) if it is
  installed and logged in; otherwise it prints exactly what to paste into
  Settings > Secrets and variables > Actions.

.EXAMPLE
  pwsh tool/release/setup-signing.ps1 -UseDebugKey
  pwsh tool/release/setup-signing.ps1 -Generate -Repo KESPREME/music_streaming_app
#>
[CmdletBinding()]
param(
  [switch]$UseDebugKey,
  [switch]$Generate,
  [string]$Repo = 'KESPREME/music_streaming_app',
  [string]$Out = (Join-Path $PSScriptRoot '..\..\android\release.jks')
)

$ErrorActionPreference = 'Stop'

if (-not ($UseDebugKey -xor $Generate)) {
  Write-Host 'Choose exactly one of -UseDebugKey or -Generate (see Get-Help).' -ForegroundColor Yellow
  exit 64
}

function New-Password { -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ }) }

if ($UseDebugKey) {
  $store = Join-Path $HOME '.android\debug.keystore'
  if (-not (Test-Path $store)) { throw "No debug keystore at $store. Build the app once with Flutter first." }
  $storePass = 'android'; $alias = 'androiddebugkey'; $keyPass = 'android'
  Write-Host "Using the debug key at $store" -ForegroundColor Cyan
} else {
  $store = (Resolve-Path (Split-Path $Out -Parent)).Path + '\' + (Split-Path $Out -Leaf)
  if (Test-Path $store) { throw "$store already exists. Move it away first; this script will not overwrite a key." }
  $storePass = New-Password; $keyPass = $storePass; $alias = 'minemusic'
  $keytool = (Get-Command keytool -ErrorAction SilentlyContinue)?.Source
  if (-not $keytool) { throw 'keytool not found. Install a JDK (17+) or run from Android Studio''s terminal.' }
  & $keytool -genkeypair -v -storetype JKS -keystore $store -alias $alias -keyalg RSA -keysize 2048 `
    -validity 10000 -storepass $storePass -keypass $keyPass -dname 'CN=Mine Music, O=Mine Music, C=US'
  if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
  Write-Host "`nKeystore written to $store" -ForegroundColor Green
  Write-Host 'BACK IT UP NOW (with the passwords below). It is gitignored; losing it strands every installed copy.' -ForegroundColor Yellow
  Write-Host "  alias:    $alias"
  Write-Host "  password: $storePass"
}

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($store))
$secrets = [ordered]@{
  ANDROID_KEYSTORE_BASE64   = $b64
  ANDROID_KEYSTORE_PASSWORD = $storePass
  ANDROID_KEY_ALIAS         = $alias
  ANDROID_KEY_PASSWORD      = $keyPass
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
$loggedIn = $false
if ($gh) { & gh auth status 2>$null | Out-Null; $loggedIn = ($LASTEXITCODE -eq 0) }

if ($gh -and $loggedIn) {
  foreach ($k in $secrets.Keys) {
    $secrets[$k] | & gh secret set $k --repo $Repo
    if ($LASTEXITCODE -ne 0) { throw "gh secret set $k failed" }
    Write-Host "set secret $k" -ForegroundColor Green
  }
  Write-Host "`nDone. Push to master and the Release workflow will publish the first OTA build." -ForegroundColor Cyan
} else {
  Write-Host "`nGitHub CLI not available or not logged in. Add these as repository secrets" -ForegroundColor Yellow
  Write-Host "(https://github.com/$Repo/settings/secrets/actions):`n"
  foreach ($k in $secrets.Keys) {
    if ($k -eq 'ANDROID_KEYSTORE_BASE64') {
      $file = Join-Path $PSScriptRoot 'keystore.base64.txt'
      Set-Content -Path $file -Value $b64 -NoNewline
      Write-Host "  $k = (contents of $file  - delete it afterwards)"
    } else {
      Write-Host "  $k = $($secrets[$k])"
    }
  }
}

# The certificate fingerprint, so you can confirm CI's APK matches what is installed.
$keytoolForFp = (Get-Command keytool -ErrorAction SilentlyContinue)?.Source
if ($keytoolForFp) {
  Write-Host "`nCertificate SHA-256 (CI prints the same line in the run summary):" -ForegroundColor Cyan
  & $keytoolForFp -list -v -keystore $store -alias $alias -storepass $storePass 2>$null | Select-String 'SHA256:'
}
