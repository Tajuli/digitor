$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host 'Verifying Digitor UI-only / DigitorEngine ownership boundary...'

$pubspec = Get-Content 'pubspec.yaml' -Raw
if ($pubspec -notmatch 'digitor_engine_ffi:\s*\r?\n\s*git:') {
  throw 'digitor_engine_ffi must be consumed from the DigitorEngine repository.'
}
if ($pubspec -notmatch 'url:\s*https://github\.com/Tajuli/DigitorEngine\.git') {
  throw 'digitor_engine_ffi must point to Tajuli/DigitorEngine.'
}
if ($pubspec -notmatch 'path:\s*dart/digitor_engine_ffi') {
  throw 'digitor_engine_ffi must use the Engine-owned Dart/Flutter package.'
}
if ($pubspec -notmatch 'ref:\s*[0-9a-fA-F]{40}') {
  throw 'DigitorEngine dependency must be pinned to an exact 40-character commit SHA.'
}

$forbiddenDependencyPatterns = @(
  '^\s*ffmpeg_kit_flutter',
  '^\s*video_compress:',
  '^\s*media_kit:',
  '^\s*opencv',
  '^\s*image:'
)
foreach ($pattern in $forbiddenDependencyPatterns) {
  if ($pubspec -match $pattern) {
    throw "UI repository contains a media-processing dependency forbidden by the Engine ownership boundary: $pattern"
  }
}

$forbiddenSourcePatterns = @(
  'Process\.run\([^\r\n]*(ffmpeg|ffprobe)',
  'DynamicLibrary\.open\([^\r\n]*digitor_engine',
  'package:ffi/ffi\.dart',
  'dart:ffi'
)

$dartFiles = Get-ChildItem -Path 'lib' -Recurse -Filter '*.dart' -File
foreach ($file in $dartFiles) {
  $source = Get-Content $file.FullName -Raw
  foreach ($pattern in $forbiddenSourcePatterns) {
    if ($source -match $pattern) {
      $relative = $file.FullName.Substring($repoRoot.Length).TrimStart('\')
      throw "UI repository crosses the native Engine boundary in $relative (pattern: $pattern)"
    }
  }
}

Write-Host 'Boundary verification passed: Digitor remains UI/UX-only and DigitorEngine remains authoritative.'
