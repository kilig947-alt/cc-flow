# Browser Extension First-Pairing Design

## Goal

Make the Chrome and Edge toolbar action self-explanatory on first use without removing its existing page-saving behavior.

## Interaction

- When no pairing token is stored, clicking the CC FLOW toolbar icon opens the extension options page instead of attempting to save the active page.
- The options page explains that the token comes from CC FLOW's Productivity Connection settings, provides the token field, and confirms a successful save.
- Saving a non-empty token writes it to extension-local storage. The background worker observes the change and immediately sends the existing authenticated heartbeat to CC FLOW.
- Once a token exists, clicking the toolbar icon keeps the current behavior: it sends the active HTTP or HTTPS page to Browser Resources.
- The extension options page remains available from Chrome/Edge's extension menu so users can replace or remove the token later.

## Error and Edge Cases

- An empty token never counts as paired. Clicking the toolbar icon continues to open the options page.
- Non-HTTP(S) tabs are not submitted. The extension shows a short badge failure state rather than silently doing nothing.
- A successful page save shows a short badge confirmation. A failed bridge request shows an error badge and does not report success.
- Safari uses the same conditional options-page behavior for explicit page saving, while download monitoring remains unavailable through Safari WebExtensions.

## Files

- `BrowserExtensions/Shared/background.js`: conditional toolbar routing and badge feedback.
- `BrowserExtensions/Shared/options.html`: clearer first-pairing instructions.
- `BrowserExtensions/Shared/options.js`: input validation and save confirmation.
- `BrowserExtensions/README.md`: installation and first-pairing steps for Chrome, Edge, and Safari.

## Verification

- Validate JavaScript syntax with `node --check`.
- Rebuild all extension bundles with `./scripts/build-browser-extensions.sh`.
- Validate all generated manifests and confirm the generated bundles contain the shared background/options assets.
- Run the focused productivity test suite to ensure the native bridge protocol still accepts the heartbeat and resource events.
