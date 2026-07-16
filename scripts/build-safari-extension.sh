#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
"$ROOT/scripts/build-browser-extensions.sh"
OUTPUT="${1:-$ROOT/BrowserExtensions/SafariApp}"
rm -rf "$OUTPUT"
xcrun safari-web-extension-converter "$ROOT/BrowserExtensions/dist/Safari" \
  --project-location "$OUTPUT" \
  --app-name "CC FLOW Safari" \
  --bundle-identifier "ai.ccflow.safari-extension" \
  --swift --macos-only --copy-resources --no-open --no-prompt --force
echo "Safari Xcode container generated at $OUTPUT"
