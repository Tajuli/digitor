param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'release'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$boundaryVerifier = Join-Path $PSScriptRoot 'verify_engine_boundary.ps1'
if (-not (Test-Path $boundaryVerifier)) {
  throw "Engine boundary verifier not found: $boundaryVerifier"
}

Write-Host 'Verifying Digitor UI-only / DigitorEngine ownership boundary...'
& $boundaryVerifier
if ($LASTEXITCODE -ne 0) {
  throw "Engine boundary verification failed with exit code $LASTEXITCODE"
}

Write-Host 'Enabling Flutter Windows desktop support...'
flutter config --enable-windows-desktop

if (-not (Test-Path 'windows\CMakeLists.txt')) {
  Write-Host 'Generating the Windows Flutter host...'
  flutter create --platforms=windows --project-name digitor .
}

Write-Host 'Resolving DigitorEngine Flutter package...'
flutter pub get

$configPath = (Resolve-Path '.dart_tool\package_config.json').Path
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$package = $config.packages |
  Where-Object { $_.name -eq 'digitor_engine_ffi' } |
  Select-Object -First 1

if (-not $package) {
  throw 'digitor_engine_ffi was not found in .dart_tool/package_config.json'
}

$rootUri = [Uri]$package.rootUri
if ($rootUri.IsAbsoluteUri) {
  $packageRoot = $rootUri.LocalPath
} else {
  $packageRoot = [IO.Path]::GetFullPath(
    (Join-Path (Split-Path $configPath) $package.rootUri)
  )
}

$provisioner = Join-Path $packageRoot 'tool\provision_ffmpeg_windows.ps1'
if (-not (Test-Path $provisioner)) {
  throw "DigitorEngine Windows FFmpeg provisioner not found: $provisioner"
}

Write-Host 'Provisioning DigitorEngine Windows FFmpeg SDK/runtime...'
& $provisioner
if ($LASTEXITCODE -ne 0) {
  throw "FFmpeg provisioning failed with exit code $LASTEXITCODE"
}

Write-Host "Building Digitor Windows ($Mode)..."
if ($Mode -eq 'debug') {
  flutter build windows --debug
} else {
  flutter build windows --release
}

Write-Host 'Digitor Windows build completed.'
