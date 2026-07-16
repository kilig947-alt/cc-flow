#!/bin/bash
# Build an ad-hoc signed CC FLOW app and package it as a styled DMG.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${CC_FLOW_BUILD_DIR:-${TRAE_FLOW_BUILD_DIR:-$PROJECT_DIR/build/unsigned}}"
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"
RELEASE_DIR="${CC_FLOW_RELEASE_DIR:-${TRAE_FLOW_RELEASE_DIR:-$PROJECT_DIR/releases/unsigned}}"
PROJECT_FILE="${CC_FLOW_PROJECT_FILE:-${TRAE_FLOW_PROJECT_FILE:-CCFlow.xcodeproj}}"
SCHEME="${CC_FLOW_SCHEME:-${TRAE_FLOW_SCHEME:-CCFlow}}"

if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: ./scripts/package-unsigned.sh"
    echo "Builds CC FLOW with ad-hoc signing and creates CCFlow-<version>.dmg."
    exit 0
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$RELEASE_DIR"

xcodebuild \
    -project "$PROJECT_DIR/$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_IDENTITY=- \
    build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/CC FLOW.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: App not found at $APP_PATH" >&2
    exit 1
fi

codesign --force --deep --sign - --preserve-metadata=identifier,entitlements "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$RELEASE_DIR/CCFlow-$VERSION.dmg"

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

"$SCRIPT_DIR/create-styled-dmg.sh" \
    --volname "CC FLOW" \
    --source "$STAGING" \
    --output "$DMG_PATH" \
    --app-name "CC FLOW.app"

echo "Created $DMG_PATH"
