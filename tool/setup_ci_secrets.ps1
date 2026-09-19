# One-time: uploads the Android signing material to GitHub Actions secrets
# so the app-branch workflow can sign releases with the SAME key as the
# locally built APK (same key = in-place upgrades keep working).
#
# Run from anywhere:  powershell -File tool/setup_ci_secrets.ps1
# Requires: gh CLI authenticated as Architect.

$ErrorActionPreference = 'Stop'
$repo = 'Sconl/isconl-agent'
$keys = 'C:\Users\PC\dev\keys'
$pw = (Get-Content "$keys\isconl-apk-keystore-password.txt" -Raw).Trim()
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$keys\isconl-apk.keystore"))

$b64 | gh secret set ANDROID_KEYSTORE_B64 --repo $repo
$pw  | gh secret set ANDROID_KEYSTORE_PASSWORD --repo $repo
'isconl' | gh secret set ANDROID_KEY_ALIAS --repo $repo
$pw  | gh secret set ANDROID_KEY_PASSWORD --repo $repo

gh secret list --repo $repo
Write-Host "Done. The Build app workflow can now sign releases." -ForegroundColor Green
