#!/bin/bash
# Archives the app and uploads it to App Store Connect for TestFlight.
# Needs: an app record for com.bureau.liveairspace in App Store Connect with the platform added (tvOS, iOS, macOS),
# your team in Config/Local.xcconfig, and Xcode signed in to your Apple ID (Xcode > Settings > Accounts).
# Usage: Tools/testflight.sh [tvos|ios|macos|all] [build-number]
#   Defaults to tvos. The build number defaults to a timestamp; every upload needs a new one.
set -euo pipefail
cd "$(dirname "$0")/.."
WHICH="${1:-tvos}"
BUILD="${2:-$(date +%y%m%d%H%M)}"

upload() {  # $1 label, $2 scheme, $3 destination
  local out; out="$(mktemp -d)"
  echo "== $1: archiving build $BUILD..."
  xcodebuild archive -project LiveAirspace.xcodeproj -scheme "$2" -destination "$3" \
    -archivePath "$out/App.xcarchive" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" | tail -3
  echo "== $1: uploading to App Store Connect..."
  xcodebuild -exportArchive -archivePath "$out/App.xcarchive" -exportOptionsPlist Config/ExportOptions.plist \
    -exportPath "$out/export" -allowProvisioningUpdates | tail -5
}

case "$WHICH" in
  tvos)  upload "Apple TV" "Live Airspace (tvOS)" "generic/platform=tvOS" ;;
  ios)   upload "iPhone/iPad" "Live Airspace (iOS & macOS)" "generic/platform=iOS" ;;
  macos) upload "Mac" "Live Airspace (iOS & macOS)" "generic/platform=macOS" ;;
  all)
    upload "Apple TV" "Live Airspace (tvOS)" "generic/platform=tvOS"
    upload "iPhone/iPad" "Live Airspace (iOS & macOS)" "generic/platform=iOS"
    upload "Mac" "Live Airspace (iOS & macOS)" "generic/platform=macOS" ;;
  *) echo "Usage: $0 [tvos|ios|macos|all] [build-number]"; exit 1 ;;
esac
echo "Done. Builds appear in App Store Connect > TestFlight after processing (usually 5-20 minutes)."
