# Immediate Left Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all CC FLOW-owned waiting from left-feature notifications so received events enter presentation routing immediately.

**Architecture:** Make `ProductivityProactiveEventCenter` an ordered synchronous queue rather than a timed aggregation buffer. Remove the separate presentation cooldown in `NotchView`; the existing automatic-notification policy remains the single gate for active, quiet, smart-suppressed, fullscreen, panel-open, and temporarily muted states.

**Tech Stack:** Swift 5, Combine `ObservableObject`, SwiftUI, XCTest, Xcode build system.

## Global Constraints

- Do not change browser extension protocol or download transition detection.
- Do not change compact broadcast's 5-second visible duration.
- Preserve quiet-open and fullscreen deferral, temporary reminder mute discard, and sound independence.
- Every left-feature event must remain individually ordered and consumable.

---

### Task 1: Make productivity event publication synchronous

**Files:**
- Modify: `CCFlow/Services/Productivity/ProductivityProactiveEventCenter.swift`
- Modify: `CCFlowTests/ProductivityFeatureTests.swift`

**Interfaces:**
- Consumes: `publish(targetFeatureID:kind:summary:count:)` call sites in browser, mail, and calendar services.
- Produces: the existing `pendingEvents`, `nextEvent`, and `consume(_:)` interface with immediate, ordered events.

- [ ] **Step 1: Replace aggregation tests with immediate-delivery tests**

Add tests that call `publish` and immediately assert `pendingEvents.count == 1`, then publish two events for the same target and assert their separate kinds, summaries, counts, and sequence order without sleeping.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests/ProductivityFeatureTests
```

Expected: the immediate assertions fail because the current center waits five seconds and aggregates same-feature events.

- [ ] **Step 3: Remove the timed aggregation buffer**

Update `ProductivityProactiveEventCenter` so `publish` increments `nextSequence` and appends a `ProductivityProactiveEvent` synchronously. Remove `PendingEvent`, `aggregationInterval`, `pendingByFeature`, `emissionTasks`, and `emit(targetFeatureID:)`. Keep the 100-event queue cap and consumed-sequence bookkeeping unchanged.

- [ ] **Step 4: Run focused tests and verify they pass**

Run the command from Step 2.

Expected: all `ProductivityFeatureTests` pass without timer sleeps.

- [ ] **Step 5: Commit the event-center change**

```bash
git add CCFlow/Services/Productivity/ProductivityProactiveEventCenter.swift CCFlowTests/ProductivityFeatureTests.swift
git commit -m "fix(notifications): publish left events immediately"
```

### Task 2: Remove the left-feature presentation cooldown

**Files:**
- Modify: `CCFlow/UI/Views/NotchView.swift`

**Interfaces:**
- Consumes: immediate events through `ProductivityProactiveEventCenter.shared.$pendingEvents`.
- Produces: `presentNextProductivityNotificationIfPossible()` with no artificial post-expansion wait.

- [ ] **Step 1: Remove cooldown state and checks**

Delete `productivityNotificationCooldownUntil`, the branch that schedules a retry until that date, and the assignment that sets it to `Date().addingTimeInterval(5)` after a successful expansion. Preserve retries for `.defer`, active completion UI, inline text input, settings popovers, and failed presentation.

- [ ] **Step 2: Build and run notification routing tests**

Run:

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test-without-building \
  -only-testing:CCFlowTests/ProductivityFeatureTests \
  -only-testing:CCFlowTests/AutomaticNotificationPresentationPolicyTests \
  -only-testing:CCFlowTests/CompactBroadcastCoordinatorTests
```

Expected: build succeeds and all selected tests pass.

- [ ] **Step 3: Run prototype regression tests**

```bash
swift test --package-path Prototype
```

Expected: all Prototype tests pass.

- [ ] **Step 4: Commit the presentation change**

```bash
git add CCFlow/UI/Views/NotchView.swift
git commit -m "fix(notifications): remove left presentation cooldown"
```
