#!/bin/bash
# Build, notarize, and package a Developer ID release of CC FLOW.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${CC_FLOW_BUILD_DIR:-${TRAE_FLOW_BUILD_DIR:-$PROJECT_DIR/build/release}}"
EXPORT_PATH="$BUILD_DIR/export"
RELEASE_DIR="${CC_FLOW_RELEASE_DIR:-${TRAE_FLOW_RELEASE_DIR:-$PROJECT_DIR/releases/signed}}"
NOTARY_PROFILE="${CC_FLOW_NOTARY_KEYCHAIN_PROFILE:-${TRAE_FLOW_NOTARY_KEYCHAIN_PROFILE:-CCFlow}}"
GENERATE_APPCAST="${CC_FLOW_GENERATE_APPCAST:-${TRAE_FLOW_GENERATE_APPCAST:-0}}"
SPARKLE_GENERATE_APPCAST="${CC_FLOW_SPARKLE_GENERATE_APPCAST:-${TRAE_FLOW_SPARKLE_GENERATE_APPCAST:-generate_appcast}}"

if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: ./scripts/package-release.sh"
    echo "Builds, notarizes, and packages CC FLOW using notarytool profile $NOTARY_PROFILE."
    exit 0
fi

"$SCRIPT_DIR/build.sh"

APP_PATH="$EXPORT_PATH/CC FLOW.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: App not found at $APP_PATH" >&2
    exit 1
fi

mkdir -p "$RELEASE_DIR"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
NOTARY_ZIP="$BUILD_DIR/CCFlow-$VERSION-notarization.zip"
STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$RELEASE_DIR/CCFlow-$VERSION.dmg"

rm -f "$NOTARY_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

"$SCRIPT_DIR/create-styled-dmg.sh" \
    --volname "CC FLOW" \
    --source "$STAGING" \
    --output "$DMG_PATH" \
    --app-name "CC FLOW.app"

xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

if [[ "$GENERATE_APPCAST" == "1" ]]; then
    if ! command -v "$SPARKLE_GENERATE_APPCAST" >/dev/null 2>&1; then
        echo "ERROR: Sparkle generate_appcast not found: $SPARKLE_GENERATE_APPCAST" >&2
        echo "Set CC_FLOW_SPARKLE_GENERATE_APPCAST to the executable path." >&2
        exit 1
    fi

    APPCAST_DIR="$RELEASE_DIR/appcast"
    rm -rf "$APPCAST_DIR"
    mkdir -p "$APPCAST_DIR"
    cp "$DMG_PATH" "$APPCAST_DIR/"
    "$SPARKLE_GENERATE_APPCAST" "$APPCAST_DIR"
fi

echo "Created $DMG_PATH"
