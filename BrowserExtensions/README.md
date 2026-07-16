# CC FLOW browser extensions

Run `./scripts/build-browser-extensions.sh`, then load `BrowserExtensions/dist/Chrome` or `dist/Edge` as an unpacked extension. Copy the pairing token from CC FLOW settings into the extension options page.

For Safari, build the same source with Xcode's Safari Web Extension converter and sign the generated container with your Apple Developer identity:

```sh
xcrun safari-web-extension-converter BrowserExtensions/dist/Safari --project-location /tmp/CCFlowSafariExtension --app-name "CC FLOW Safari"
```

The extension only has access to downloads, the active tab after an explicit toolbar click, local extension storage, and the CC FLOW loopback endpoint. It does not request general browsing-history or all-sites access.
