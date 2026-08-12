param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'release'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host 'Preparing Digitor Android host...'
flutter --version
flutter create --platforms=android --project-name digitor .
flutter pub get

Write-Host "Building Digitor Android ($Mode)..."
if ($Mode -eq 'release') {
    flutter build apk --release
    $artifact = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk'
} else {
    flutter build apk --debug
    $artifact = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-debug.apk'
}

if (-not (Test-Path $artifact)) {
    throw "Flutter completed without the expected APK: $artifact"
}

Write-Host "Digitor Android build complete: $artifact"
