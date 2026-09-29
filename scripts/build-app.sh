#!/bin/zsh
# Builds iPhoneUse.app. CoreBluetooth only works from a signed bundle with a usage string;
# a bare binary is killed by TCC.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"

APP="build/iPhoneUse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/iphone-use" "$APP/Contents/MacOS/iphone-use"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
sign() { codesign --force --options runtime --entitlements Resources/iPhoneUse.entitlements --sign "$1" "$APP"; }
# A locked keychain (SSH, sandboxed shells) fails with errSecInternalComponent; fall back to ad hoc.
sign "$IDENTITY" 2>/dev/null || { IDENTITY="-"; sign "$IDENTITY"; }
echo "built $APP (signed: $IDENTITY)"
