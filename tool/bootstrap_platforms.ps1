$ErrorActionPreference = 'Stop'

Write-Host 'Generating Digitor platform hosts...'
flutter config --enable-windows-desktop
flutter create --platforms=android,windows --project-name digitor .
flutter pub get

Write-Host 'Android and Windows hosts are ready.'
Write-Host 'iOS/macOS hosts must be generated on macOS with tool/bootstrap_apple.sh.'
