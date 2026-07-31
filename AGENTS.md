# AGENTS.md

This file is a routing layer for coding agents working in this repo. Keep it short. Put long-lived detail in nearby code, focused docs, or tests.

## Mission

- CC FLOW is a macOS menu bar app that surfaces Dynamic Island-style status for Claude Code, Codex, Antigravity, and four compatible TRAE variants.
- Claude Code, Codex, and Antigravity are the default integrations. TRAE, TRAE CN, TRAE WORK, and TRAE WORK CN are optional compatibility clients shown when detected or already configured.
- The main runtime path is:
  - Claude Code, Codex, Antigravity, or TRAE hook events
  - `CCFlowBridge` with a provider/client profile
  - monitoring and service layers
  - `SessionStore`
  - `SessionMonitor` and `NotchViewModel`
  - SwiftUI Flow Island UI (left: custom HTML / session detail, right: variant counts / jump-back)
- There are two important codepaths:
  - `CCFlow/`: the shipping Xcode app (Bundle ID `ai.ccflow.app`)
  - `Prototype/`: a SwiftPM prototype with focused tests and reference implementations

## Start Here

- Product overview: `README.md`
- App entry: `CCFlow/App/CCFlowApp.swift`, `CCFlow/App/AppDelegate.swift`
- Provider and client profiles: `CCFlow/Models/SessionProvider.swift`, `CCFlow/Models/ClientProfile.swift`, `CCFlow/Models/TraeVariant.swift`
- Flow Island left region (compact feature / expanded feature container / session detail): `CCFlow/UI/Views/FlowIslandLeftRegion.swift` (expanded slot renders `LeftFeatureContainerView`), `CCFlow/UI/Views/NotchView.swift` headerRow (compact slot)
  - Left feature system: `LeftFeatureStore` (enabled features, `compactFeatureID`, `expandedActiveFeatureID`, ordering, migration from legacy dual-selection) — `CCFlow/Services/LeftFeatures/LeftFeatureStore.swift`
  - Built-in features: music (`NowPlayingProvider` via MediaRemote private framework, dlopen-loaded), shelf (`ShelfStore` for temporary file transfer with AirDrop), newsnow (NewsNow remote instance), and mineradio (Mineradio Bridge compat layer) — `CCFlow/Services/LeftFeatures/Music/`, `CCFlow/Services/LeftFeatures/Shelf/`, `CCFlow/Services/LeftFeatures/Mineradio/`
  - Left feature kinds: built-in `music` / `shelf` / `newsnow(baseURL:)` / `mineradio(pageURL:)`, user `customArea` (local HTML directory via `CustomAreaStore`), user `webURL` (remote URL loaded directly by `CustomAreaWebView` with `ContentSource.remoteURL`). `LeftFeature.customIconName` overrides the default SF Symbol; `LeftFeature.customDisplayName` holds the `.webURL` name. When `appendWebURLFeature` is called without an explicit `iconName`, `FaviconFetcher` auto-fetches the site favicon and writes `img:favicon-<host>.png` to `customIconName`; URL edits re-fetch if the current icon is still an auto-fetched favicon. Built-in `newsnow` and `mineradio` features auto-fetch their site favicon on first launch via `LeftFeatureStore.fetchBuiltinFaviconIfNeeded` (only when `customIconName` is nil; skipped if already fetched or user-customized). The new/edit feature sheets (`addCustomAreaSheet` in `SettingsWindowView`, `EditableCustomAreaView`) place the URL field first in webURL mode; on URL change (debounced 600ms) `FaviconFetcher.fetchMetadata` fetches both favicon and site `<title>` in parallel and auto-fills the icon and name fields — name is overwritten only if empty or still the last auto-filled value; icon is overwritten only if unset or still an auto-fetched favicon; user-edited values are preserved.
  - Mineradio Bridge compat layer (Spec: `mineradio-bridge-compat-layer`): `.mineradio(pageURL:)` loads `https://mineradio.art/` in a WKWebView with a `WKUserScript` (`MineradioBridgeUserScript`) injected at `atDocumentStart` that simulates the Mineradio Bridge browser extension's content script. The page's `window.postMessage` PING/MINERADIO_API messages are routed to `MineradioBridgeCoordinator` → `MineradioBridgeEngine` (JavaScriptCore running the extension's esbuild-bundled `bridge-bundle.js` + `bridge-polyfills.js`). JSC polyfills provide `fetch` (→ URLSession), `chrome.cookies` (→ `WKHTTPCookieStore`), `URL`/`atob`/`crypto` etc. Binary endpoints (`/api/audio`, `/api/cover`) are proxied directly in Swift with forged Referer. Login: `MineradioLoginView` loads platform login pages (网易云/QQ/酷狗) in a separate WKWebView sharing `WKWebsiteDataStore.default()` cookies; a 2s poll detects login cookies and triggers `refreshLoginState`. Settings UI exposes three platform login-status buttons + URL edit + enable toggle. Built-in mineradio/newsnow features auto-fetch website favicon on first launch via `LeftFeatureStore.fetchBuiltinFaviconIfNeeded` (only when `customIconName` is nil; reuses `FaviconFetcher`). Lyrics on Flow Island use a **dual-source playback state** strategy: (1) `MineradioBridgeCoordinator` subscribes to `NowPlayingProvider.$nowPlaying` via Combine (`startNowPlayingSubscription`, called by `AppDelegate` when mineradio feature is enabled, and lazily on `attach(to:)`); system MediaRemote hooks all `<audio>` playback at OS level including WKWebView's detached `new Audio()` elements that MutationObserver/DOM scan cannot find — MediaRemote provides `elapsed`/`duration`/`isPlaying` and is detected as Mineradio source by `isMineradioNowPlayingInfo` (title contains "Mineradio" or source contains "trae"/"flow"). (2) `MineradioBridgeUserScript.playbackHookSource` (injected after Bridge script) uses a three-tier audio hook as fallback: patch `window.Audio` constructor + `HTMLMediaElement.prototype.play` + `HTMLMediaElement.prototype.src` setter; also intercepts outgoing `MINERADIO_API` messages (`/api/song/url` netease→`query.id`, `/api/qq/song/url`→`query.mid`, `/api/kg/song/url`→`query.hash`, plus `/api/lyric`, `/api/song/like/check`) to extract song ID + provider, posting `{type:'song', songId, provider, title, artist}` to `mineradioPlayback` handler (title best-effort from DOM with `isLikelySongTitle` filter excluding page title "Mineradio — 在线音乐可视化播放器"). On song ID change `MineradioBridgeCoordinator.handlePlaybackMessage` calls `/api/lyric?id=<songId>` via Bridge engine, parses LRC (`MineradioLyricParser.parse`), tracks current line by `elapsed` (`MineradioLyricParser.currentLine` binary search). `MineradioCompactView` renders current lyric (opacity transition) → song title (filtered) → static "Mineradio". Only netease lyrics supported (qq/kugou fall back to title). Empty-lyric song IDs cached. **Limitation**: songId requires the WKWebView to have been expanded at least once (so Bridge script can intercept `MINERADIO_API`); playback state (elapsed/duration/isPlaying) works without expansion via MediaRemote. `AppDelegate` starts `NowPlayingProvider` when music OR mineradio feature is enabled.
  - Compact slot renders `LeftFeatureStore.compactFeature` (auto rule: music when playing → first enabled → placeholder); expanded slot renders `LeftFeatureContainerView` (switcher bar + main content area)
  - Expanded panel size is draggable from the bottom-left/bottom-right corners of the opened Flow Island (subtle rounded corner indicators overlaid in `NotchView`); live size goes through `NotchViewModel.openedSizeOverride`, and the final size is persisted per-feature in `LeftFeature.expandedWidth` / `expandedHeight`. Docked sessions, proactive notifications, and left features without a custom width share `Settings.expandedPanelWidth` (default 900pt, clamped to `screenWidth - 64pt`); fallback height is 460pt.
  - Compact slot height is configurable via `Settings.compactLeftHeight` (24–80pt), `NotchViewModel.closedSize.height` follows it
- Flow Island right region (variant counts / jump-back): `CCFlow/UI/Views/FlowIslandRightRegion.swift`
- Jump-back to TRAE IDE: `CCFlow/Services/Window/TraeSessionLauncher.swift`
- Custom area data model and store: `CCFlow/Services/CustomAreas/CustomArea.swift`, `CCFlow/Services/CustomAreas/CustomAreaStore.swift`
  - `CustomAreaStore` only manages directory metadata (CRUD/sort/entry-point detection); left feature selection and ordering migrated to `LeftFeatureStore` (compact/expanded selection no longer lives here)
  - `addArea` / `removeArea` notify `LeftFeatureStore.appendCustomAreaFeature` / `removeCustomAreaFeature` to keep feature list in sync
  - `CustomArea.iconName` / `allowsNetworkAccess` override the feature icon and gate external network in the WebView; `defaultVariant` defaults to `.traeWorkCN` for new areas
  - `addAreaWithAutoGeneratedDirectory(name:iconName:allowsNetworkAccess:defaultVariant:)` generates `custom-areas/<sanitized-name>/index.html` from the built-in interactive template (push hint / fetch public API / localStorage counter)
  - Compact slot height: `Settings.compactLeftHeight` (CGFloat, 24–80, default 24)
- Custom area WebView wrapper (with JS Bridge for compact hints): `CCFlow/Services/CustomAreas/CustomAreaWebView.swift`
  - `ContentSource` enum (`.localArea(CustomArea)` / `.remoteURL(URL)`) selects `loadFileURL` vs `load(URLRequest)`; `allowsNetworkAccess` (from `CustomArea.allowsNetworkAccess` or `true` for remote) gates `http/https` navigation and `fetch`
  - JS Bridge: HTML calls `window.webkit.messageHandlers.ccFlowHint.postMessage({ text, duration })` to push a hint to the compact Flow Island; `{ action: "clear" }` clears it. Default duration 5000ms.
  - Hint state store: `CCFlow/Services/CustomAreas/CustomAreaHintStore.swift` (auto-dismiss after duration, one active hint per area)
  - Compact hint view: `CCFlow/UI/Views/LeftFeatures/CustomAreaHintCompactView.swift` (overlays `CustomAreaWebView` in compact slot when active)
  - Hint visibility toggle: `Settings.showCompactHintEnabled` (default true), shown in settings when `compactFeatureID != nil` (non-auto)
  - Remote URL keep-alive: `Settings.keepWebURLAliveWhenCollapsed` (default true). When on, expanded-slot `CustomAreaWebView` for `.remoteURL` source (`.webURL` / `.newsnow`) and `.mineradio` source passes `keepsAlive: true`; `CustomAreaWebViewCache` holds a strong reference to the WKWebView so it survives Flow Island collapse (audio/JS/network continue). On next expand, `makeNSView` rebinds a fresh `Coordinator` (removes + re-adds message handlers including Mineradio Bridge `apiMessageHandlerName` / `binaryMessageHandlerName` / `playbackMessageHandlerName`, updates navigation/ui delegates, re-attaches `MineradioBridgeCoordinator`) and reuses the cached instance without reloading. Cache is evicted on feature disable / removal / URL edit and cleared when the setting is turned off. `dismantleNSView` moves the dismantled WKWebView into an offscreen borderless `NSWindow` (`CustomAreaWebViewCache.hostInOffscreenWindow`) so macOS does not suspend JavaScript while the Flow Island is collapsed; `makeNSView` removes it from that host window when expanded again.
- Custom area file watcher (DispatchSource): `CCFlow/Services/CustomAreas/CustomAreaWatcher.swift`
- Sandbox-external bookmark persistence: `CCFlow/Services/CustomAreas/SecurityScopedBookmarkStore.swift`
- Custom area settings UI: `CCFlow/UI/Views/CustomAreaSettingsView.swift`
- Bridge runtime paths (cc-flow branded): `CCFlow/Services/Hooks/BridgeRuntimePaths.swift`
- Docked/detached presentation orchestration: `CCFlow/App/IslandPresentationCoordinator.swift`, `CCFlow/App/WindowManager.swift`. Multi-display switches are serialized in `WindowManager.setupNotchWindow()` and old docked windows are fully torn down (`contentViewController = nil`, `orderOut`, `close`) in `IslandPresentationCoordinator.invalidate()` / `recreateDockedWindow()` to prevent duplicate Flow Islands from appearing across screens.
- First-run surface-mode onboarding and mode-switch UI: `CCFlow/App/AppDelegate.swift`, `CCFlow/UI/Window/SettingsWindowController.swift`, `CCFlow/UI/Views/SettingsWindowView.swift`
- Main state hub: `CCFlow/Services/State/SessionStore.swift`
- Session association cache: `CCFlow/Services/State/SessionAssociationStore.swift`
- Session bridge for UI: `CCFlow/Services/Session/SessionMonitor.swift`
- Notch state and layout: `CCFlow/Core/NotchViewModel.swift`, `CCFlow/UI/Views/NotchView.swift`
- App-wide low-power policy for background polling, event monitoring, UI animation tiers, and silent update gating: `CCFlow/Core/EnergyGovernor.swift`
- User idle protection for temporarily routing blocking approvals/questions back to terminals: `CCFlow/Core/UserIdleAutoProtection.swift`, `CCFlow/Core/Settings.swift`, `CCFlow/Services/Hooks/BridgeRuntimeConfigWriter.swift`
- Detached floating capsule: `CCFlow/UI/Window/DetachedIslandWindowController.swift`, `CCFlow/UI/Views/DetachedIslandPanelView.swift`, `CCFlow/UI/Views/IslandOpenedContentView.swift`
  - Detached pet interactions now keep the pet anchored in place while hover/click previews expand sideways as message-bubble lists; trace both the panel layout and window-anchor math together when changing this flow
  - Expanded content routing is shared with the docked notch through `IslandOpenedContentView` + `IslandExpandedRouteResolver`; keep hover/click/notification semantics aligned instead of reintroducing detached-only content priorities
  - Pet detach keeps the docked Flow Island fully functional: `NotchViewModel.shouldHideWindowPresentation` and `shouldSuppressAutomaticPresentation` no longer return `true` when `presentationMode == .detached`. `beginDetachedPresentation` no longer corrupts docked state — it writes only detached-local twins (`detachedContentType`, `detachedOpenedMeasuredHeight`) plus `presentationMode`/`detachedDisplayMode` and cancels `hoverTimer`. The docked `contentType`/`status`/`openReason`/`currentChatSession`/`openedMeasuredHeight` stay at their pre-detach values. `redockAfterDetached` resets only the detached twins and flips `presentationMode = .docked`; it also closes an opened docked panel (`status = .closed`) so the transparent expanded window does not continue to block clicks in the upper screen area after the pet returns. `panelSize(for:)` picks `detachedContentType`/`detachedOpenedMeasuredHeight` when `style == .detached`, else the docked shared fields. The pet visual is hidden in `NotchView` (`closedRightMascotRegion` / `closedIconOnlyContent`) via `presentationMode == .detached` gating. Detached-side readers (`DetachedIslandPanelView`, `DetachedIslandWindowController.$detachedContentType` Combine, `maybePresentNextCompletionNotification`, `IslandOpenedContentView` route) all read `detachedContentType` when `style == .detached`.
  - Detached pet resize via scroll-to-zoom: `DetachedIslandWindow.sendEvent` routes `.scrollWheel` events to `petScrollWheelHandler` → `handlePetScrollWheel`, which adjusts `AppSettings.floatingPetCustomScale` (minimum 0.5, no upper limit, 0 = follow `floatingPetSizeMode`) by ±8% per scroll tick. `DetachedIslandPetMetrics(customScale:)` clamps to a minimum of 0.5; `petMetrics(for:)` checks custom scale first. `floatingPetCustomScale` changes trigger `scheduleWindowSizeUpdate()`; the update preserves the pet's leading edge and vertical center so the task bubble stays vertically aligned with the pet's center line and horizontally attached to the pet's left side, while the pet grows toward the right to avoid pushing the bubble (and the enlarged window) over other windows on the left.
  - First-run surface-mode onboarding defaults to Flow Island: `PresentationModeWelcomeWindowController.present` selects `.notch` as the initial mode when `AppSettings.presentationModeOnboardingPending` is true, so new users start with the pet on the Flow Island rather than the floating pet.
  - Normal app launch resets `surfaceMode` to `.notch` in `AppDelegate.applicationDidFinishLaunching` (non-test builds), so the pet always starts inside the Flow Island unless the user is actively in the onboarding flow.
- Global shortcuts and shortcut persistence: `CCFlow/Services/Shared/GlobalShortcutManager.swift`, `CCFlow/Utilities/GlobalShortcut.swift`, `CCFlow/Core/Settings.swift`, `CCFlow/UI/Views/SettingsWindowView.swift`
- TRAE hook ingress: `Prototype/Sources/IslandBridge/`, `CCFlow/Services/Hooks/HookInstaller.swift`, `CCFlow/Services/Hooks/HookSocketServer.swift`
  - `CCFlowBridge` is the unified TRAE hook entrypoint and is responsible for terminal, tmux, and IDE terminal context capture before envelopes hit Swift code
- Terminal and focus control: `CCFlow/Services/Tmux/`, `CCFlow/Services/Window/`, `CCFlow/Utilities/TerminalVisibilityDetector.swift`
  - Terminal focus flows currently cover iTerm2, Ghostty, Terminal.app, tmux, and IDE-hosted terminals
- Provider/client routing: bridge envelopes are normalized in `CCFlow/Services/Hooks/HookSocketServer.swift`, stored on `SessionState`, and launched via `CCFlow/Services/Window/SessionLauncher.swift`
- Client profile registry: TRAE variant client branding / recognition is centralized in `CCFlow/Models/ClientProfile.swift` and routed through `TraeVariant.allCases`
- TRAE terminal focus infrastructure: `CCFlow/Services/Window/TerminalSessionFocuser.swift` (shared actor for focusing TRAE IDE/hosted terminal sessions)
- Session list UI: `CCFlow/UI/Views/SessionListView.swift`
- Client mascot theme pack system: `CCFlow/Services/Mascot/` (theme manifest, frame layout, scanner, watcher, built-in themes, sprite cache), `CCFlow/UI/Components/MascotView.swift`, `CCFlow/UI/Views/MascotSettingsView.swift`
- App updates and release notes: `CCFlow/Services/Update/`, `CCFlow/UI/Views/ReleaseNotesWindowView.swift`, `CCFlow/UI/Window/ReleaseNotesWindowController.swift`
- Sparkle build configuration: `Config/App.xcconfig`, `Config/LocalSecrets.xcconfig`, `docs/sparkle-release.md`

## Repo Map

- `CCFlow/App`: app lifecycle, window setup, screen observation
- `CCFlow/Core`: notch geometry, shared state, app settings, selectors
- `CCFlow/Models`: domain models for sessions, events, tools, phases
- `CCFlow/Services`: ingestion, socket handling, state management, tmux, windows, updates
- `CCFlow/Services/CustomAreas`: custom HTML area data model, store, WebView wrapper, DispatchSource watcher, built-in templates, sandbox-external bookmarks, remote-URL WebView keep-alive cache. All runtime paths use the `cc-flow` identifier.
- `CCFlow/Services/LeftFeatures`: left feature system — `LeftFeature` model, `LeftFeatureStore` registry (enabled features, compact/expanded selection, ordering, legacy migration), `Music/NowPlayingProvider` (MediaRemote private framework via dlopen), `Shelf/ShelfStore` (temporary file transfer with AirDrop), `Mineradio/` (Bridge compat layer: `MineradioBridgeEngine` JSContext running esbuild-bundled extension JS, `MineradioBridgeCoordinator` WKWebView↔JSC bridge + binary proxy, `MineradioBridgeUserScript` content-script injection, `MusicPlatform` three-platform login model), `FaviconFetcher` (auto-fetch website favicon for `.webURL` features — tries Google s2/favicons → DuckDuckGo → site `/favicon.ico`, caches to `~/Library/Application Support/cc-flow/icons/favicon-<host>.png`, re-encoded as PNG). All left feature selection is centralized here; `CustomAreaStore` only manages directory metadata.
- `CCFlow/Services/Mascot`: codex-compatible pet theme pack system — manifest decoding, frame layout, multi-source scanner (builtin/codex/user), DispatchSource watcher, built-in claude fallback, sprite sheet cache. All theme pack IDs flow through `MascotKind.themeID`. Deleting a non-builtin theme in `MascotSettingsView` triggers `MascotThemeScanner.deleteTheme`, which removes matching directories from both `~/.cc-flow/pets/` and `~/.codex/pets/` so the pet does not reappear due to source merging; if the deleted theme was selected, it resets to the default. Built-in themes can also be deleted: their IDs are recorded in `AppSettings.deletedBuiltinMascotThemeIDs` and filtered out during scanning; the settings UI shows a "恢复内置宠物" button to restore them.
- `CCFlow/Services/Update`: Sparkle updater bridge, appcast/release-notes loading, update state publishing
- `CCFlow/Services/Window/TerminalSessionFocuser.swift`: shared TRAE terminal focus actor used by `SessionLauncher` for TRAE IDE/hosted terminal focus
- `CCFlow/UI`: SwiftUI views, reusable components, AppKit-backed window controllers
- `CCFlow/Resources`: hook assets, entitlements, bundled fonts
- `Prototype`: Swift package prototype and testbed
- `Prototype/Tests`: logic-level unit tests plus process/socket e2e coverage for `IslandBridge`, hook mapping, and install flows
- `scripts`: release, signing, and packaging automation
- `Config`: checked-in build configuration defaults plus optional local-only secrets overrides

## Change Routing

- If you change hook payload shape or hook event semantics, update these together:
  - `Prototype/Sources/IslandBridge/`
  - `CCFlow/Services/Hooks/HookSocketServer.swift`
  - `CCFlow/Models/SessionEvent.swift`
  - `CCFlow/Services/State/SessionStore.swift`
  - the affected UI under `CCFlow/UI/`
- If you change TRAE variant definitions, bundle IDs, URL schemes, or hook paths, start in `CCFlow/Models/TraeVariant.swift` and trace through `ClientProfile`, `HookInstaller`, `HookSocketServer` (variant routing in `makeClientInfo`), `FlowIslandRightRegion`, and `TraeSessionLauncher` so all four variants stay consistent.
- Flow Island left-region compact feature view and expanded feature container: `CCFlow/UI/Views/LeftFeatures/MusicCompactView.swift`, `ShelfCompactView.swift`, `MusicExpandedView.swift`, `ShelfExpandedView.swift`, `LeftFeatureContainerView.swift`, `LeftFeatureSwitcherBar.swift`. Expanded-panel resize handles (bottom-left/bottom-right corners) live in `CCFlow/UI/Views/NotchView.swift` (`LeftExpandedResizeHandle` overlay on `styledNotchLayout`, only for docked `.customExpanded`), driving `NotchViewModel.openedSizeOverride` live and persisting to `LeftFeature.expandedWidth` / `expandedHeight` via `LeftFeatureStore.setExpandedSize` on drag end.
- Flow Island left-region feature selection: `LeftFeatureStore.compactFeatureID` (compact mode, nil = auto) and `LeftFeatureStore.expandedActiveFeatureID` (expanded mode, nil = first enabled). Compact slot height is `Settings.compactLeftHeight` (24–80). Hook envelope JSON is still surfaced via `SessionState.lastEnvelopeJSON` (written by `HookSocketServer`) but no longer rendered in the UI.
- If you change Flow Island left/right layout, trace through `NotchView` (headerRow integration with `LeftFeatureStore.compactFeature` + dynamic width + `compactLeftHeight` height), `FlowIslandLeftRegion` (expanded slot via `LeftFeatureContainerView`), `LeftFeatureContainerView`, `LeftFeatureSwitcherBar`, `MusicCompactView` / `ShelfCompactView` / `MusicExpandedView` / `ShelfExpandedView`, `FlowIslandRightRegion`, `CustomAreaWebView`, `LeftFeatureStore` (feature selection + ordering + per-feature expanded size), `CustomAreaStore` (directory metadata only), `NotchViewModel` (`closedSize.height` follows `compactLeftHeight`; `openedSizeOverride` drives live resize), and `NotchWindowController` (dragging keeps mouse events enabled) so compact/expanded states, feature rendering, height configuration, resize handles, and variant counts stay aligned.
- If you change left feature system (music / shelf / newsnow / mineradio / customArea / webURL kinds, selection, ordering, migration, custom icon/name, per-feature expanded size), trace through `LeftFeatureStore`, `LeftFeature`, `LeftFeatureContainerView`, `LeftFeatureSwitcherBar`, `NowPlayingProvider` / `MediaRemoteBridge`, `ShelfStore`, `CustomAreaStore` (add/remove lifecycle + `iconName` / `allowsNetworkAccess`), `CustomAreaWebView` (`ContentSource` + `allowsNetworkAccess`), `NotchView.headerRow` (compact dispatch, now covers `.webURL` / `.mineradio`), `FlowIslandLeftRegion` (expanded dispatch), `NotchViewModel` (`openedSizeOverride`), and `SettingsWindowView.leftContent` (settings UI: feature row actions + new/edit sheet) so feature list, selection, ordering, icon/name overrides, expanded size persistence, network gating, and migration stay consistent.
- If you change the Mineradio Bridge compat layer (Spec: `mineradio-bridge-compat-layer`), trace through `MineradioBridgeEngine` (JSContext + polyfills + native callbacks), `MineradioBridgeCoordinator` (WKWebView↔JSC message routing + binary proxy + login state + playback/lyric state), `MineradioBridgeUserScript` (content-script injection + `__mineradioDeliverJSON` + `playbackHookSource` audio/`MINERADIO_API` interception), `MineradioLyric` (`MineradioLyricLine` + `MineradioPlaybackState` + `MineradioLyricParser` LRC parser + `currentLine` binary search), `MusicPlatform` (three-platform login model), `CustomAreaWebView` (`.mineradio` `ContentSource` + Bridge script injection + `decidePolicyFor` cross-host allow + message handler routing incl. `mineradioPlayback`), `MineradioLoginView` (platform login WKWebView + cookie poll), `MineradioCompactView` (lyric → title → static fallback), `LeftFeatureContainerView` (`.mineradio` expanded branch), `NotchView` (compact dispatch), `SettingsWindowView` (login status buttons + URL edit + logout), `LeftFeatureStore` (`ensureBuiltinMineradioFeature` + `updateMineradioPageURL`), and `CCFlow/Resources/MineradioBridge/bridge-bundle.js` + `bridge-polyfills.js` (checked-in generated artifacts; regenerate from upstream Mineradio Bridge extension source via esbuild if extension upgrades) so Bridge protocol, cookie sharing, login flow, lyric tracking, and UI dispatch stay aligned.
- If you change custom area data model, update `CustomArea`, `CustomAreaStore`, `CustomAreaWatcher`, `CustomAreaWebView`, `CustomAreaHintStore`, `CustomAreaHintCompactView`, `CustomAreaSettingsView`, and `LeftFeatureStore` (customArea feature lifecycle) together. All runtime paths must use the `cc-flow` identifier. Built-in preset directories (weather/cpu/stock/pomodoro) have been removed; only user-added directories are managed. The JS Bridge hint API (`ccFlowHint` message handler) flows: HTML `postMessage` → `CustomAreaWebView.Coordinator` → `CustomAreaHintStore` → `CustomAreaHintCompactView` (compact slot overlay in `NotchView`); visibility gated by `Settings.showCompactHintEnabled`.
- If you change jump-back-to-IDE behavior, inspect `TraeSessionLauncher` (URL scheme activation) and `FlowIslandRightRegion` (variant row buttons) so all four variants route correctly.
- If you change bridge environment variables or socket/config paths, keep the `CC_FLOW_*` → `TRAE_FLOW_*` → `ISLAND_*` fallback chain intact in `Prototype/Sources/IslandBridge/main.swift` and `Prototype/Sources/IslandShared/BridgeRuntimeConfig.swift`.
- If you change provider/client detection or click-through behavior, trace through `HookSocketServer`, `SessionStore`, `SessionState`, `SessionLauncher`, and the session list / hover UI so labels and launch targets stay in sync.
- All client integration flows through the provider/client profile registry. When adding or changing client behavior, start in `CCFlow/Models/ClientProfile.swift`, `CCFlow/Models/SessionProvider.swift`, and `CCFlow/Models/TraeVariant.swift`; do not add ad-hoc client switches elsewhere.
- If you change how sessions are associated across relaunches or between hook ingress paths, inspect both `SessionStore` and `SessionAssociationStore` so cached client metadata stays compatible.
- If you change session lifecycle or transitions, start in `SessionStore`. Avoid ad-hoc state mutation elsewhere.
  - Current rule: provider-originated end events should preserve the session in `.ended` so it stays visible in the list; only explicit user archive/removal should delete it from `SessionStore`.
  - Primary list rule: sessions with no new activity for 30 minutes should auto-hide from the primary list until fresh hook/file activity updates `lastActivity`; sessions that need manual attention should stay visible.
- If you change notch sizing, opening behavior, or visibility, inspect both `NotchViewModel` and `NotchView`.
- If you change docked/detached Island transitions or drag-to-detach behavior, trace through `IslandPresentationCoordinator`, `WindowManager`, `NotchViewModel`, `NotchWindowController`, and `DetachedIslandWindowController` together so gesture gating, content resolution, and re-docking stay aligned.
- If you change the persisted surface mode or first-run onboarding, trace through `AppDelegate`, `WindowManager`, `IslandPresentationCoordinator`, `SettingsWindowController`, `SettingsWindowView`, and `Settings.swift` together so launch-time routing and in-app switching stay aligned.
- If you change global shortcuts, shortcut persistence, or shortcut hints, trace through `CCFlow/Services/Shared/GlobalShortcutManager.swift`, `CCFlow/Utilities/GlobalShortcut.swift`, `CCFlow/Core/Settings.swift`, `CCFlow/UI/Views/SettingsWindowView.swift`, `CCFlow/UI/Components/GlobalShortcutHintView.swift`, and the relevant notch/chat/session-list views together so registration, customization, and visible hints stay aligned.
- If you change background polling, global event monitors, silent update scheduling, or idle animation behavior, inspect `CCFlow/Core/EnergyGovernor.swift` plus the affected service/view so active sessions stay responsive while quiet, locked, or sleeping periods remain low-power.
- If you change built-in notification sounds or startup audio, inspect `CCFlow/Core/Settings.swift`, `CCFlow/Core/SoundPackCatalog.swift`, `CCFlow/UI/Views/SettingsWindowView.swift`, `CCFlow/App/AppDelegate.swift`, and `CCFlow/Resources/Sounds/` together so mode selection, fixed mappings, previews, and bundled assets stay aligned.
- If you change mascot theme pack selection or mascot animations, trace through `CCFlow/Services/Mascot/MascotThemeScanner.swift`, `CCFlow/Services/Mascot/MascotThemeWatcher.swift`, `CCFlow/Core/Settings.swift` (selectedMascotThemeID / mascotThemeOverrides / mascotPerClientOverrideEnabled), `CCFlow/UI/Components/MascotView.swift` (TRAE pixel art fallback vs sprite sheet rendering), and the mascot callsites in `NotchView`, `SessionListView`, `SessionHoverPreviewView`, `DetachedIslandPanelView`, and `MascotSettingsView` so scanner results, settings persistence, and previews stay aligned. Theme packs are read from `$HOME/.codex/pets/` (codex CLI) and `$HOME/.cc-flow/pets/` (user-installed).
- If you change completion-result popup behavior, trace through `SessionStore`, `SessionMonitor`, `CCFlow/UI/Views/NotchView.swift`, and `CCFlow/UI/Views/SessionCompletionNotificationView.swift` so completion detection, queueing, and auto-dismiss timing stay aligned.
- If you change tmux or terminal focusing, trace through `Services/Tmux`, `Services/Window`, and `TerminalVisibilityDetector`.
- If you change IDE terminal jump behavior, inspect `TerminalSessionFocuser` plus the integration settings UI so install state and URI schemes stay aligned.
- Long prompts, results, tool details, and transcript rows must keep full data in `SessionStore` / snapshots and apply bounded display text only at SwiftUI rendering boundaries. Prefer `SessionTextSanitizer.boundedDisplayText` for inline `Text` / Markdown content, add or preserve tests for truncation behavior, and avoid passing unbounded transcripts directly into expanded Island detail views.
- If you change app updates or release notes, trace through `CCFlow/Services/Update/`, `CCFlow/Info.plist`, the settings UI, and `scripts/create-release.sh` so appcast assets, runtime config, and update messaging stay aligned.
- If you change Sparkle configuration keys or hosting assumptions, update `Config/App.xcconfig`, `Config/LocalSecrets.example.xcconfig`, `scripts/generate-keys.sh`, and `docs/sparkle-release.md` together.
- If you only need logic-level confidence, prefer adding or updating tests under `Prototype/Tests`.

## Build And Test

- Full repo regression:
  - `./scripts/test.sh`
- App debug build:
  - `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug build`
- App release build:
  - `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Release build`
- Root Xcode unit tests:
  - `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests`
- Root Xcode UI tests:
  - `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGN_IDENTITY=- test -only-testing:CCFlowUITests`
  - macOS may block the UI test runner until a valid local signing identity is available; if `CCFlowUITests-Runner` stays launch-suspended, inspect `amfid` and `AppleSystemPolicy` logs before treating it as an app regression
- Prototype tests:
  - `swift test --package-path Prototype`
- Bridge-focused e2e slice:
  - `swift test --package-path Prototype --filter IslandBridgeE2ETests`
- Mascot GIF export for docs/resources:
  - `./scripts/render-mascots.sh`
- Release automation:
  - `./scripts/build.sh`
  - `./scripts/create-release.sh`
  - `./scripts/generate-keys.sh`
  - GitHub Actions: `.github/workflows/release-packages.yml` creates an ad-hoc signed `CCFlow-<version>.dmg` and optional Sparkle appcast for a `v*` tag or manual dispatch.
- Local release scripts assume signing and notarization tooling. They may modify `build/`, `releases/`, and `.sparkle-keys/`.

## Working Rules

- Respect existing uncommitted changes. Do not revert unrelated work.
- Prefer narrow edits. This repo currently has active changes in UI and session-flow files.
- Treat documentation upkeep as part of the change, not follow-up work.
- When writing or updating tests, do not use the user's local filesystem paths as example values; prefer repo-relative, generic, or clearly synthetic paths instead.
- Every major feature change or refactor must review and update `AGENTS.md` plus any affected adjacent docs, tests, scripts, or inline code comments that describe the old behavior.
- Prefer code search over guesswork:
  - `rg "process\\(" CCFlow`
  - `rg "Hook|hook" CCFlow`
  - `rg "TraeVariant" CCFlow Prototype`
  - `rg "tmux|Tmux" CCFlow`
- When adding new state, decide deliberately whether it belongs in:
  - SwiftUI view-local `@State`
  - shared `ObservableObject` state
  - actor-owned `SessionStore` state
- Keep localization lookups at UI or other actor-appropriate boundaries. `AppLocalization.string` is main-actor isolated on CI toolchains, so nonisolated utilities such as sanitizers, parsers, stores, and model helpers should expose localization keys or plain data instead of calling localization APIs directly.
- When adding bundled assets or fonts, make sure app startup initializes them.
- Keep this file high-signal. If a section becomes long, move the durable detail into a dedicated markdown doc and link it here.

## Verification Checklist

- Can the main Xcode scheme still build?
- If the change is a major feature or refactor, was `AGENTS.md` reviewed and updated to reflect the new structure, ownership, entrypoints, or verification steps?
- If session ingestion changed, do TRAE hook sessions still appear and update across all four variants (TRAE / TRAE CN / TRAE WORK / TRAE WORK CN)?
- If session lifecycle changed, do ended sessions remain visible until the user archives them, and do final TRAE messages still land before the row settles into `.ended`?
- If idle-session visibility changed, do sessions auto-hide after 30 minutes of inactivity and reappear when a new message or hook event arrives?
- If detached Island behavior changed, can the docked notch still click-open normally, drag-detach from closed/opened states, and re-dock cleanly without duplicate windows?
- If approval or intervention flows changed, do approve, deny, and answer paths still resolve cleanly?
- If focus logic changed, does tmux and non-tmux behavior still degrade safely?
- If release tooling changed, avoid running notarization or signing steps unless the task explicitly requires them.

## Current Reality

- The main shipping target is the Xcode project, not the Swift package under `Prototype/`.
- The root project now includes `CCFlowTests` and `CCFlowUITests` targets for app-level state and settings-window coverage.
- `Prototype/Tests` remains the fastest place for logic-level unit tests plus process/socket e2e coverage.
- Sparkle update discovery is expected to use the GitHub Releases `latest/download/appcast.xml` asset unless a local override explicitly replaces it.
- The worktree may already be dirty. Check `git status` before broad edits.
- Removed codepaths (do not reintroduce):
  - `CCFlow/Services/Codex/`, `CCFlow/Services/Runtime/`, `CCFlow/Services/Remote/`, `CCFlow/Services/Usage/`, `CCFlow/Core/FeatureFlags.swift`, `CCFlow/Services/Window/IDEExtensionInstaller.swift`, `CCFlow/UI/Views/CodexSessionView.swift`, native runtime start/terminate APIs on `SessionMonitor`, and `refreshUsageState()` on `SessionMonitor`. Residual `isNativeRuntimeSession` / `ingress == .nativeRuntime` checks are inert (no ingress path sets `.nativeRuntime` anymore) but kept to minimize churn.
  - Non-TRAE editor support (VSCode/Cursor/Windsurf/Zed/Qoder/JetBrains): `Prototype/Sources/IslandApp/Core/IDEExtensionInstaller.swift`, `ManagedIDEExtensionProfile`, `IDESessionFocusStrategy`, `ClientProfileRegistry.ideExtensionProfiles`, `HookInstallEntryTemplate.direct`, `SessionClientInfo.ideHostProfile` / `isHostedInIDE` / `interactionOriginDisplayName` / `ideHostBadgeLabel(for:)`, `SessionState.ideHostBadgeLabel`, `SessionLauncher.activateHostedIDEFallback` / `activateIDEWindow` / `routeIDEWorkspaceWindow` / `ideCandidateBundleIdentifiers` / `focusExistingIDEWorkspaceWindow` / `waitForIDEWindowActivation`, `TerminalSessionFocuser.focusHostedSession`, `SettingsWindowView.ideTint`. `TerminalAppRegistry.ideBundleIdentifiers` 仅含 `com.trae.app`。
  - Non-TRAE client recognition layer (Codex/Gemini/Hermes/OpenCode/CodeBuddy/WorkBuddy/Copilot/OpenClaw/Kimi/Qoder/QoderWork/Cursor): `SessionStore.appendHermesHookChatItem` / `appendGeminiHookChatItem`, Kimi Stop 特殊处理, Codex provider 残留死代码, `SessionListView.isCodexSubagentCompactPresentation`, `Prototype/Sources/IslandApp/Core/CodexAppServerMonitor.swift`, `AgentProvider.codex` / `.copilot` / `.kimi` / `.gemini`, 非 TRAE 客户端的 `ManagedHookClientProfile` / `SessionClientProfile` 注册与 hook 资产安装方法。
  - Claude 协议命名重命名为 TRAE：`SessionProvider.claude` → `.trae`（Codable 保留旧值 "claude" 兼容）、`SessionClientKind.claudeCode` → `.trae`（兼容 "claudeCode"）、`HookProtocolFamily.claudeHooks` → `.traeHooks`（兼容 "claudeHooks"）、`AgentProvider.claude` → `.trae`、`bridgeSource: "claude"` → `"trae"`。`~/.claude/` 等运行时文件路径约定保留（TRAE 复用）。
  - Global residual non-TRAE client strings removed: `MascotKind.claude` title/subtitle "Claude Code" / "桌前橘猫" → "TRAE" / "TRAE 默认宠物", `BuiltInMascotThemes.claude.displayName` → "TRAE", `HookSocketServer` default name fallback → "TRAE", `ChatView` "Claude Code needs your input" → "TRAE needs your input", remaining "Claude Code" / "Claude Hooks" entries in Localizable.strings.
  - Removed: Flow Island left-region JSON display and dual-selection model: `CCFlow/UI/Components/CompactJSONView.swift`, `CCFlow/UI/Views/JSONExpandedContentView.swift`, `CCFlow/UI/Views/CustomNotchExpandedContentView.swift`, `Settings.showJSONInCompactNotch`, `Settings.showCustomHTMLWhenExpanded`, `CustomAreaStore.compactAreaID` / `expandedAreaID` / `compactArea` / `expandedArea` / `selectCompactArea` / `selectExpandedArea`, `IslandExpandedRoute.jsonExpanded`, `NotchContentType.jsonExpanded`, `NotchViewModel.presentJSONExpanded()`. Legacy `customAreaCompactID` / `customAreaExpandedID` / `customAreaSelectedID` UserDefaults keys are migrated to `LeftFeatureStore` (`leftFeatureCompactID` / `leftFeatureExpandedActiveID`) on first launch. `SessionState.lastEnvelopeJSON` is retained for hook data continuity but no longer rendered.
  - The left Flow Island now uses a unified feature system (`LeftFeatureStore`) with four kinds: music (MediaRemote private framework via dlopen, covers all system players), shelf (temporary file transfer with AirDrop, cleared on app exit), customArea (user-added HTML directories, optional `allowsNetworkAccess` for external fetch), and webURL (remote URL loaded directly by `CustomAreaWebView` via `ContentSource.remoteURL`, network always on). Each feature may override its SF Symbol via `LeftFeature.customIconName` (customArea via `CustomArea.iconName`); `.webURL` carries its name in `LeftFeature.customDisplayName`. Compact slot auto-selects music when playing else first enabled feature; expanded slot shows a switcher bar + main content area aligned with boringnotch style. The settings feature row exposes open-directory / jump-to-`defaultVariant` (TRAE Work CN by default) / delete / enable actions for `.customArea`, delete / enable for `.webURL`; clicking icon or name opens the edit sheet.
  - Custom HTML areas support a JS Bridge hint API: HTML calls `window.webkit.messageHandlers.ccFlowHint.postMessage({ text: "提醒", duration: 3000 })` to push a time-limited hint (default 5000ms) that overlays the compact Flow Island slot; `{ action: "clear" }` clears it early. Hints flow through `CustomAreaWebView.Coordinator` → `CustomAreaHintStore` → `CustomAreaHintCompactView` and are gated by `Settings.showCompactHintEnabled` (shown in settings only when `compactFeatureID != nil`). `CustomAreaStore.addTestHTMLArea()` creates a built-in test HTML area demonstrating the API.
- Claude Code, Codex, Antigravity, and the four TRAE variants (TRAE / TRAE CN / TRAE WORK / TRAE WORK CN) are supported. `TraeSessionLauncher` handles jump-back to TRAE IDE via TRAE URL scheme. `TerminalSessionFocuser.focusSession` handles iTerm2 / Terminal.app / Ghostty / cmux plain terminals.
- Intentionally retained: `~/.claude/` runtime file paths (TRAE reuses the Claude protocol) and `~/.codex/pets/` mascot theme directory convention (TRAE reuses the Codex CLI pet directory).
