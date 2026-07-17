# Latest-Only Compact Broadcast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace compact broadcast queues with one latest-only slot per side.

**Architecture:** Keep `CompactBroadcastCoordinator` as the SwiftUI-facing owner, but simplify its value state to two optional active broadcasts. Enqueue replaces the corresponding side immediately; consume clears it; the coordinator resets that side's five-second dismissal task on every replacement.

**Tech Stack:** Swift 5, Combine, XCTest.

## Global Constraints

- Preserve independent left-feature and session sides.
- Preserve the five-second visible duration.
- Do not change upstream reliable delivery trackers or event queues.
- Same-side newest broadcast always wins, regardless of target.

---

### Task 1: Replace compact broadcast queues with latest-only slots

**Files:**
- Modify: `CCFlow/Services/Notifications/CompactBroadcastCoordinator.swift`
- Modify: `CCFlowTests/CompactBroadcastCoordinatorTests.swift`

**Interfaces:**
- Consumes: existing `enqueue(_:)`, `consume(_:)`, `clear()`, and `setTargetValidator(_:)` callers.
- Produces: existing `activeLeftFeature` and `activeSession` published properties without queued successors.

- [ ] **Step 1: Write failing latest-only state tests**

Replace queue-advancement assertions with tests that enqueue two different broadcasts on one side and immediately assert the second is active, then consume and assert the side is nil. Keep a test showing left and session slots remain independent.

- [ ] **Step 2: Run tests and verify failure**

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test-without-building -parallel-testing-enabled NO -only-testing:CCFlowTests/CompactBroadcastCoordinatorTests
```

Expected: latest-only assertions fail because different targets currently enter a waiting queue.

- [ ] **Step 3: Delete queue storage and advancement**

Remove `leftQueue`, `sessionQueue`, `nextValid`, and `queuedCount`. Make `CompactBroadcastQueueState.enqueue` assign the valid broadcast directly to the selected active slot. Make `consume` set the selected active slot to nil. Keep `clear` and target validation.

- [ ] **Step 4: Verify coordinator dismissal replacement**

Ensure `CompactBroadcastCoordinator.enqueue` cancels the same-side dismissal task before scheduling the replacement. Add an async test with a short display duration proving the replacement remains visible for its own full duration and then disappears without a successor.

- [ ] **Step 5: Run focused notification tests**

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test-without-building -parallel-testing-enabled NO \
  -only-testing:CCFlowTests/CompactBroadcastCoordinatorTests \
  -only-testing:CCFlowTests/AutomaticNotificationPresentationPolicyTests \
  -only-testing:CCFlowTests/ProductivityFeatureTests
```

Expected: all selected tests pass.

- [ ] **Step 6: Run Prototype regression tests**

```bash
swift test --package-path Prototype
```

Expected: all Prototype tests pass.

- [ ] **Step 7: Commit**

```bash
git add CCFlow/Services/Notifications/CompactBroadcastCoordinator.swift CCFlowTests/CompactBroadcastCoordinatorTests.swift
git commit -m "fix(notifications): keep only latest compact broadcast"
```
