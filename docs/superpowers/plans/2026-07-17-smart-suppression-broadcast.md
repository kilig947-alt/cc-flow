# Smart Suppression Broadcast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Smart Suppression downgrade Active notifications to compact broadcasts while Quiet notifications always broadcast and no eligible notification is silently consumed.

**Architecture:** Add a pure presentation-policy resolver with four results: expand, broadcast, defer, and discard. Route session pending/manual/completion producers and productivity producers through that resolver before acknowledging their events.

**Tech Stack:** Swift 5, SwiftUI, Combine, XCTest, Xcode 17.

## Global Constraints

- Active without Smart Suppression expands the corresponding route.
- Active with Smart Suppression broadcasts only when expansion would otherwise occur.
- Quiet always broadcasts when closed and defers while the panel is open.
- Temporary reminder mute may discard; fullscreen-hidden state defers.
- Sound remains controlled only by `soundEnabled`.

---

### Task 1: Central presentation policy

**Files:**
- Create: `CCFlow/Services/Notifications/AutomaticNotificationPresentationPolicy.swift`
- Create: `CCFlowTests/AutomaticNotificationPresentationPolicyTests.swift`

**Interfaces:**
- Produces: `AutomaticNotificationPresentationDecision` cases `expand`, `broadcast`, `defer`, `discard`.
- Produces: `AutomaticNotificationPresentationPolicy.resolve(mode:smartSuppressionTriggered:isPanelOpen:isFullscreenSuppressed:isReminderMuted:)`.

- [ ] Add matrix tests for Active/Quiet, Smart Suppression, open/closed panel, fullscreen, and reminder mute.
- [ ] Run focused tests and verify they fail before the policy exists.
- [ ] Implement the pure resolver with reminder mute highest priority, fullscreen defer second, Quiet broadcast/defer third, and Active expand/broadcast last.
- [ ] Run focused tests and verify all matrix cases pass.

### Task 2: Route all notification producers through policy

**Files:**
- Modify: `CCFlow/UI/Views/NotchView.swift`
- Modify: `CCFlowTests/NotificationDeliveryPolicyTests.swift`

**Interfaces:**
- Consumes: `AutomaticNotificationPresentationPolicy.resolve(...)`.
- Preserves: `CompactBroadcastCoordinator` independent left/session queues.

- [ ] Add delivery tests for retaining Quiet notifications while open and acknowledging only after broadcast.
- [ ] Add a `notificationPresentationDecision` helper in `NotchView` using current mode, terminal visibility, panel state, fullscreen suppression, and reminder mute.
- [ ] Route pending sessions: discard, defer/retry, broadcast/acknowledge, or expand/acknowledge.
- [ ] Route manual attention with the same decision and per-target acknowledgement.
- [ ] Route productivity events: defer while Quiet/open, downgrade Active/suppressed to left broadcast, otherwise expand.
- [ ] Route completion and compaction notifications: direct expansion only for `expand`; drain completion queue to session broadcasts for `broadcast`; retain for `defer`.
- [ ] On panel close, retry pending sessions, manual attention, completion queue, and productivity queue.
- [ ] Run focused tests, Prototype tests, Debug build, and `git diff --check`.
- [ ] Request code review before committing implementation.
