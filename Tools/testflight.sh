#!/bin/bash
# Archives the tvOS app and uploads it to App Store Connect for TestFlight.
# Needs: an app record for com.bureau.liveairspace in App Store Connect, your team in Config/Local.xcconfig,
# and Xcode signed in to your Apple ID (Xcode > Settings > Accounts).
# Usage: Tools/testflight.sh [build-number]   (defaults to a timestamp; every upload needs a new one)
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${1:-$(date +%y%m%d%H%M)}"
OUT="$(mktemp -d)"
echo "Archiving build $BUILD..."
xcodebuild archive -project LiveAirspace.xcodeproj -scheme "Live Airspace (tvOS)" -destination "generic/platform=tvOS" \
  -archivePath "$OUT/LiveAirspace.xcarchive" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" | tail -3
echo "Uploading to App Store Connect..."
xcodebuild -exportArchive -archivePath "$OUT/LiveAirspace.xcarchive" -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates | tail -5
echo "Done. The build appears in App Store Connect > TestFlight after processing (usually 5-20 minutes)."
