#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$ROOT/BrowserExtensions/dist"
rm -rf "$OUT"
for browser in Chrome Edge Safari; do
  mkdir -p "$OUT/$browser"
  cp "$ROOT/BrowserExtensions/$browser/manifest.json" "$OUT/$browser/manifest.json"
  cp "$ROOT/BrowserExtensions/Shared/background.js" "$OUT/$browser/background.js"
  cp "$ROOT/BrowserExtensions/Shared/options.html" "$OUT/$browser/options.html"
  cp "$ROOT/BrowserExtensions/Shared/options.js" "$OUT/$browser/options.js"
  cp "$ROOT/CCFlow/Assets.xcassets/AppIcon.appiconset/icon_16x16.png" "$OUT/$browser/icon16.png"
  cp "$ROOT/CCFlow/Assets.xcassets/AppIcon.appiconset/icon_32x32.png" "$OUT/$browser/icon32.png"
  cp "$ROOT/CCFlow/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" "$OUT/$browser/icon128.png"
done
for manifest in "$OUT"/*/manifest.json; do
  /usr/bin/plutil -lint "$manifest" >/dev/null 2>&1 || /usr/bin/python3 -m json.tool "$manifest" >/dev/null
done
echo "Browser extensions built in $OUT"
