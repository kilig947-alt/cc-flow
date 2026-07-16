# CC FLOW browser extensions

Run `./scripts/build-browser-extensions.sh`, then load `BrowserExtensions/dist/Chrome` or `dist/Edge` as an unpacked extension. Copy the pairing token from CC FLOW settings into the extension options page.

For Safari, generate the installable macOS Safari Web Extension container, then build/sign it with your Apple Developer identity:

```sh
./scripts/build-safari-extension.sh
```

The extension only has access to downloads, the active tab after an explicit toolbar click, local extension storage, and the CC FLOW loopback endpoint. It does not request general browsing-history or all-sites access.

Chrome and Edge report real-time download events through their `downloads` APIs. Safari does not expose that Web Extension permission on the supported macOS target, so its extension handles explicit page saving while CC FLOW monitors Safari's local Downloads folder for completed/in-progress files.
