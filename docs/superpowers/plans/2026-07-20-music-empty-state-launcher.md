# Music Empty-State Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the expanded music feature's passive empty state with a button that opens the most recently detected music player, falling back to Apple Music.

**Architecture:** Add a focused `MusicPlayerApplication` value type that maps Now Playing source names to application identities, resolves installed applications, and persists the last detected player through injectable `UserDefaults`. `NowPlayingProvider` records each recognized source and exposes the resolved launch target and launch action. `MusicExpandedView` renders the target's native icon and a labeled launch button only when no track is available.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSWorkspace`, Foundation `UserDefaults`, XCTest.

## Global Constraints

- Support Apple Music, Spotify, 网易云音乐, and QQ 音乐 using their existing bundle identifier candidates.
- Persist the last recognized player across app launches.
- Fall back to Apple Music when the remembered player is unavailable.
- Keep the playing-state layout and controls unchanged.
- Use a labeled, keyboard-accessible native button with an explicit accessibility hint.
- Do not add a player picker or settings surface.

---

### Task 1: Player identity and persistence

**Files:**
- Create: `CCFlow/Services/LeftFeatures/Music/MusicPlayerApplication.swift`
- Create: `CCFlowTests/MusicPlayerApplicationTests.swift`

**Interfaces:**
- Consumes: Now Playing `source: String`, injectable `UserDefaults`, and an installed-bundle predicate.
- Produces: `MusicPlayerApplication.from(source:)`, `MusicPlayerApplicationStore.record(source:)`, and `MusicPlayerApplicationStore.preferredApplication(isInstalled:)`.

- [x] **Step 1: Write failing tests**

Cover source aliases, persistence, remembered-player preference, unavailable-player fallback, and Apple Music fallback.

- [x] **Step 2: Run tests to verify failure**

Run: `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests/MusicPlayerApplicationTests`

Expected: FAIL because the application model and store do not exist.

- [x] **Step 3: Implement the focused application model and store**

Define the supported application name, bundle identifier candidates, source alias mapping, persisted identifier key, and deterministic fallback resolution. Keep AppKit launching out of the model so resolution is unit-testable.

- [x] **Step 4: Run tests to verify success**

Run the same focused `xcodebuild` command.

Expected: PASS.

### Task 2: Provider launch API and empty-state button

**Files:**
- Modify: `CCFlow/Services/LeftFeatures/Music/NowPlayingProvider.swift`
- Modify: `CCFlow/UI/Views/LeftFeatures/MusicExpandedView.swift`
- Modify: `CCFlowTests/NowPlayingProviderTests.swift`

**Interfaces:**
- Consumes: `MusicPlayerApplicationStore` and `ClientAppLocator.applicationURL(bundleIdentifiers:)`.
- Produces: provider properties for the preferred application/icon and `openPreferredPlayer()`.

- [x] **Step 1: Add provider behavior tests where practical**

Verify recognized Now Playing sources are recorded without changing playback state semantics.

- [x] **Step 2: Implement provider recording and launching**

Record sources on both polling and stream updates. Resolve the preferred installed application, obtain its icon, and open it with `NSWorkspace.OpenConfiguration`, activating an already-running application through the same API.

- [x] **Step 3: Implement the empty-state CTA**

Replace the passive note/message stack with the resolved app icon, `未在播放`, and a bordered prominent button labeled `打开 <应用名>`. Add hover/press behavior through native button styling plus `accessibilityHint("启动最近使用的音乐播放器")`. Preserve the existing material card and playing content.

- [x] **Step 4: Run focused tests and build**

Run:

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests/MusicPlayerApplicationTests -only-testing:CCFlowTests/NowPlayingProviderTests
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: tests PASS and build succeeds.

### Task 3: Final regression review

**Files:**
- Review only: all files changed by Tasks 1–2.

**Interfaces:**
- Consumes: completed implementation.
- Produces: reviewed, regression-checked change set.

- [x] **Step 1: Inspect the final diff**

Confirm no playing-state UI changed, persistence does not write unknown sources, and launching has a safe fallback.

- [x] **Step 2: Run formatting/compiler diagnostics through the app build**

Run: `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Expected: BUILD SUCCEEDED.
