# Notification Delivery Retry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure Active-mode session and left-feature notifications are presented reliably and are acknowledged only after delivery.

**Architecture:** `SessionManualAttentionTracker` will expose peek/acknowledge semantics so transient presentation suppression cannot consume an event. `NotchView` will retain undelivered pending-session IDs, schedule bounded retries while suppression remains active, and let productivity notifications present independently from unrelated session attention.

**Tech Stack:** Swift 5, SwiftUI, Combine, XCTest, Xcode 17.

## Global Constraints

- Quiet-mode five-second broadcasts and their routing remain unchanged.
- `soundEnabled` remains the sole sound gate.
- Temporary reminder mute intentionally discards notifications.
- Smart/fullscreen suppression retains notifications for retry.
- Existing dirty changes in the main worktree must not be overwritten.

---

### Task 1: Make manual-attention delivery transactional

**Files:**
- Modify: `CCFlow/UI/Views/SessionManualAttentionTracker.swift`
- Modify: `CCFlowTests/SessionManualAttentionTrackerTests.swift`

**Interfaces:**
- Produces: `nextAttentionSession(from:) -> SessionState?`
- Produces: `acknowledge(_:)`
- Retains: `consumeNewAttentionSession(from:)` as a compatibility wrapper for detached presentation code.

- [ ] **Step 1: Add failing tracker tests**

Add tests proving repeated peek returns the same session until `acknowledge`, acknowledgement advances to a second simultaneous session, and a refreshed intervention creates a new candidate.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests/SessionManualAttentionTrackerTests
```

Expected: compilation failure because `nextAttentionSession` and `acknowledge` do not exist.

- [ ] **Step 3: Implement stable attention keys and explicit acknowledgement**

Represent each approval/question/terminal-routed prompt with a key containing session stable ID, category, and current tool/intervention identifier. Prune acknowledged keys that no longer exist, return the newest unacknowledged candidate without mutating acknowledgement state, and make the compatibility `consumeNewAttentionSession` call peek then acknowledge.

- [ ] **Step 4: Run focused tracker tests**

Expected: all `SessionManualAttentionTrackerTests` pass.

---

### Task 2: Retain session notifications and unblock productivity delivery

**Files:**
- Modify: `CCFlow/UI/Views/NotchView.swift`
- Create: `CCFlowTests/NotificationDeliveryPolicyTests.swift`

**Interfaces:**
- Produces: pure `SessionPendingDeliveryState` with `undelivered(currentIDs:)`, `acknowledge(_:)`, and `discard(_:)`.
- Uses: transactional manual-attention tracker from Task 1.

- [ ] **Step 1: Add failing delivery-state tests**

Cover retention across a suppressed attempt, acknowledgement after delivery, disappearance pruning, and explicit discard during reminder mute.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests/NotificationDeliveryPolicyTests
```

Expected: compilation failure because `SessionPendingDeliveryState` does not exist.

- [ ] **Step 3: Implement pending-session retry routing**

Replace `previousPendingIds` with `SessionPendingDeliveryState`. On reminder mute call `discard`; on smart/fullscreen suppression retain IDs and schedule a one-second retry; on Quiet enqueue broadcasts then acknowledge; on Active successfully open the session list then acknowledge. Cancel retry work when no undelivered IDs remain or the view disappears.

- [ ] **Step 4: Make manual attention acknowledge after presentation**

Peek before policy checks. During transient suppression schedule the same retry without acknowledgement. In Quiet mode acknowledge after enqueue. In Active mode acknowledge after calling the corresponding presentation route, then retry if another candidate remains.

- [ ] **Step 5: Remove cross-source productivity blocking**

Keep inline-input/settings/completion/fullscreen guards, but remove `hasPendingPermission` and `hasHumanIntervention` from the productivity guard so session attention cannot indefinitely block left-feature delivery.

- [ ] **Step 6: Run affected and regression tests**

Run focused Xcode tests, `swift test --package-path Prototype`, and a Debug build. Expected: all focused tests pass, 95 Prototype tests pass, and Debug build succeeds.

- [ ] **Step 7: Request code review**

Review notification acknowledgement timing, retry cancellation, Quiet-mode behavior, and preservation of sound independence before committing implementation.
