# Left Feature Page State Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve each expanded web feature's in-memory page state across collapse and feature switches, while reloading its configured entry page only when the active icon is clicked again.

**Architecture:** Give every expanded web feature a stable `CustomAreaWebViewCache.Key` based on its feature ID, independent of its URL. `CustomAreaWebView` always caches expanded website instances, while the existing keep-running setting controls only offscreen hosting. A monotonic reentry request in `LeftFeatureStore` lets the switcher distinguish selection from an explicit entry-page reload.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, XCTest, Xcode.

## Global Constraints

- Preserve cookies and website data when reentering.
- Do not cache compact-slot WebViews under expanded cache keys.
- Do not keep native SwiftUI features mounted.
- Preserve unrelated uncommitted workspace changes.

---

### Task 1: Feature-keyed WebView cache

**Files:**
- Modify: `CCFlow/Services/CustomAreas/CustomAreaWebViewCache.swift`
- Modify: `CCFlow/Services/CustomAreas/CustomAreaWebView.swift`

**Interfaces:**
- Produces: `CustomAreaWebViewCache.Key`, `webView(for:)`, `storeWebView(_:for:)`, `evict(for:)`, and `CustomAreaWebView.init(source:cacheKey:keepsRunningWhenHidden:)`.
- Consumes: existing `ContentSource` and offscreen host behavior.

- [ ] **Step 1: Add a stable cache key and key-based cache operations**

```swift
struct Key: Hashable, Sendable {
    let rawValue: String
    static func expanded(featureID: String) -> Key { Key(rawValue: "expanded:\(featureID)") }
}
```

Change the cache dictionary to `[Key: WKWebView]`. Keep URL eviction as a compatibility helper that removes cached views whose configured entry URL matches.

- [ ] **Step 2: Separate state caching from background execution**

Add optional `cacheKey` and `keepsRunningWhenHidden` inputs to `CustomAreaWebView`. Cache whenever `cacheKey != nil`; only call `hostInOffscreenWindow` when `keepsRunningWhenHidden` is true. A cached view that is not kept running remains strongly retained but is not placed in the offscreen window.

- [ ] **Step 3: Build the app target**

Run: `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`.

### Task 2: Explicit reentry command and icon behavior

**Files:**
- Modify: `CCFlow/Services/LeftFeatures/LeftFeatureStore.swift`
- Modify: `CCFlow/UI/Views/LeftFeatures/LeftFeatureSwitcherBar.swift`

**Interfaces:**
- Produces: `LeftFeatureReentryRequest(featureID:generation:)`, `expandedReentryRequest`, and `selectOrReenterExpandedFeature(id:)`.
- Consumes: `expandedActiveFeature?.id` and existing selection persistence.

- [ ] **Step 1: Add a monotonic request model**

```swift
struct LeftFeatureReentryRequest: Equatable {
    let featureID: String
    let generation: UInt64
}
```

Store the latest request as `@Published private(set)`. On an already-active ID, increment the generation and publish a request; otherwise call `setExpandedActiveFeature(id:)` without publishing.

- [ ] **Step 2: Route switcher clicks through the new API**

Replace the unconditional setter in `FeatureSwitcherButton` with `selectOrReenterExpandedFeature(id:)`. Keep `onSelect` so the task-list route still opens the feature panel.

- [ ] **Step 3: Evict feature-keyed cache entries on lifecycle changes**

When a website feature is disabled, deleted, or its configured entry changes, call:

```swift
CustomAreaWebViewCache.shared.evict(for: .expanded(featureID: id))
```

Also evict removed custom-area feature IDs.

### Task 3: Wire expanded web features and reload entry pages

**Files:**
- Modify: `CCFlow/UI/Views/LeftFeatures/LeftFeatureContainerView.swift`
- Modify: `CCFlow/Services/CustomAreas/CustomAreaWebView.swift`

**Interfaces:**
- Consumes: `featureStore.expandedReentryRequest` and `.expanded(featureID:)` cache keys.
- Produces: entry reload on generation changes without website-data deletion.

- [ ] **Step 1: Pass cache keys for all four website feature kinds**

For `.customArea`, `.webURL`, `.newsnow`, and `.mineradio`, construct the view with the active feature ID and the setting value:

```swift
CustomAreaWebView(
    source: source,
    cacheKey: .expanded(featureID: feature.id),
    keepsRunningWhenHidden: settings.keepWebURLAliveWhenCollapsed
)
```

- [ ] **Step 2: Pass the matching reentry generation**

Resolve the generation only when the request feature ID equals the rendered feature. In `updateNSView`, detect a new generation and call the existing `loadArea(into:context:)` exactly once. Do not clear `WKWebsiteDataStore`.

- [ ] **Step 3: Verify build and focused tests**

Run: `xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests`

Expected: all `CCFlowTests` pass. If the environment cannot launch tests, run the Debug build command and report the exact runner failure separately.

- [ ] **Step 4: Review the final diff**

Run: `git diff --check` and inspect only the task files. Confirm no unrelated dirty file was overwritten and that compact-slot constructors still omit a cache key.
