#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA_PATH="$PROJECT_DIR/build/DebugDerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/CC FLOW.app"
BUNDLE_ID="ai.ccflow.app"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: ./scripts/debug-relaunch.sh"
    echo "Incrementally builds the Debug app, quits the running CC FLOW instance, and relaunches it."
    exit 0
fi

if [[ $# -gt 0 ]]; then
    echo "ERROR: Unknown argument: $1" >&2
    echo "Run ./scripts/debug-relaunch.sh --help for usage." >&2
    exit 2
fi

cd "$PROJECT_DIR"

echo "=== Building CC FLOW (Debug) ==="
xcodebuild \
    -project CCFlow.xcodeproj \
    -scheme CCFlow \
    -configuration Debug \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: App not found at $APP_PATH" >&2
    exit 1
fi

echo ""
echo "=== Relaunching CC FLOW ==="
if pgrep -x "CC FLOW" >/dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null

    for _ in {1..50}; do
        if ! pgrep -x "CC FLOW" >/dev/null; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x "CC FLOW" >/dev/null; then
        echo "ERROR: The existing CC FLOW instance did not quit." >&2
        exit 1
    fi
fi

open "$APP_PATH"
echo "Launched: $APP_PATH"
