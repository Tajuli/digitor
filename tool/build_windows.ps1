param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'release'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

function Invoke-NativeStep {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Description,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Command
  )

  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE"
  }
}

$boundaryVerifier = Join-Path $PSScriptRoot 'verify_engine_boundary.ps1'
if (-not (Test-Path $boundaryVerifier)) {
  throw "Engine boundary verifier not found: $boundaryVerifier"
}

Write-Host 'Verifying Digitor UI-only / DigitorEngine ownership boundary...'
# PowerShell scripts report failure by throwing; they do not reliably set
# $LASTEXITCODE. Let any verifier exception propagate naturally.
& $boundaryVerifier

Write-Host 'Enabling Flutter Windows desktop support...'
Invoke-NativeStep 'Flutter Windows desktop enablement' {
  flutter config --enable-windows-desktop
}

if (-not (Test-Path 'windows\CMakeLists.txt')) {
  Write-Host 'Generating the Windows Flutter host...'
  Invoke-NativeStep 'Flutter Windows host generation' {
    flutter create --platforms=windows --project-name digitor .
  }
}

Write-Host 'Resolving DigitorEngine Flutter package...'
Invoke-NativeStep 'Flutter dependency resolution' {
  flutter pub get
}

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
# As above, a PowerShell provisioner reports failure by throwing.
& $provisioner

Write-Host "Building Digitor Windows ($Mode)..."
if ($Mode -eq 'debug') {
  Invoke-NativeStep 'Flutter Windows debug build' {
    flutter build windows --debug
  }
} else {
  Invoke-NativeStep 'Flutter Windows release build' {
    flutter build windows --release
  }
}

Write-Host 'Digitor Windows build completed.'
