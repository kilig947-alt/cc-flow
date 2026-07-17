# Quiet Notification Presentation Design

## Goal

Add an independent Active/Quiet notification presentation control to the Flow Island opened header, immediately to the left of the sound toggle. Sound muting controls only whether notification audio is generated. It must not suppress, reroute, or discard visual notifications.

Active mode preserves the current automatic notification behavior. Quiet mode replaces automatic Flow Island expansion with compact, five-second broadcasts in the closed Flow Island.

This feature applies to the pet displayed inside the Flow Island. It does not change the detached desktop pet.

## User-visible behavior

### Header controls

The opened header control order is:

1. Pin
2. Active/Quiet presentation mode
3. Sound on/off
4. Settings

The presentation button uses `bell.fill` in Active mode and `bell.slash.fill` in Quiet mode. Its tooltip and accessibility label describe the action: “Switch to Quiet mode” or “Switch to Active mode.” The persisted mode defaults to Active so upgrades do not change existing behavior.

### Active mode

All existing automatic presentation behavior remains unchanged. Session completion, errors, attention requests, compaction notices, and proactive left-feature notifications may open the Flow Island through their current routes.

### Quiet mode

Only notifications that would otherwise automatically expand the Flow Island are converted into compact broadcasts. Manual clicks, shortcuts, hover-to-open behavior unrelated to a broadcast, and pinned/open panels are unaffected.

Two broadcasts may be visible at the same time:

- Left-feature broadcasts start at the Flow Island’s left edge, extend toward the midpoint, and align their icon and text to the leading edge.
- Session broadcasts sit immediately to the left of the Flow Island pet, extend toward the midpoint, and align their icon and text to the trailing edge.

Neither broadcast may cross the Flow Island midpoint. Text is limited to one line and truncated at the tail with an ellipsis. When both sources are active, each remains within its own half and they do not cover one another. Broadcasts retain the current closed Flow Island height and visual language, with only a subtle semantic tint.

Each broadcast is visible for five seconds and then advances its side’s queue. Hovering a broadcast cancels its dismissal and opens the corresponding session detail or left feature. Once the target opens, the broadcast is removed.

Entry and exit use a short directional slide plus opacity. With Reduce Motion enabled, only opacity changes.

After dismissal, the original compact content is restored, including the selected left feature and the pet/session count region.

## Notification sources

### Sessions

Quiet mode covers the same session events that currently cause automatic presentation, including completion, errors, waiting for user input, permission/approval attention, and compaction when its existing setting enables automatic presentation. It must not create new notification categories.

Session broadcasts contain a provider/client or state icon plus a bounded summary derived from the existing session notification data. Long source content remains stored in session state; truncation happens only at the SwiftUI rendering boundary.

### Left features

Quiet mode covers both:

- Custom-area `ccFlowHint` messages.
- Proactive notifications from built-in left features such as calendar, downloads, and mail.

The broadcast carries a stable feature target, icon, display name or bounded message, and enough route information to open the matching feature on hover.

## Architecture

### Persisted setting

Introduce a codable/raw-value `NotificationPresentationMode` with `active` and `quiet` cases. Store it in `AppSettingsStore` and expose it through `AppSettings` in the same pattern as other persisted display settings.

`soundEnabled` remains the sole global gate for sound playback. No sound path may read `NotificationPresentationMode`, and no visual notification path may use `soundEnabled` as a gate.

### Broadcast model and coordinator

Introduce a main-actor `CompactBroadcastCoordinator` with a small source-neutral model:

- Stable identifier and deduplication key.
- Side: left feature or session.
- Bounded display summary and semantic icon.
- Created/expiration timestamps.
- Route target: session stable ID or left-feature ID.

The coordinator owns independent FIFO queues and one active item per side. A new item for the same target replaces the existing queued or active item so rapid updates do not spam the user. Other targets keep chronological order.

The coordinator schedules five-second dismissal work items. It validates a route target before presentation and again before opening it. Missing sessions, disabled/removed features, or invalid feature routes are discarded and the next queued item advances.

### Routing integration

Existing notification producers decide between their current Active route and the Quiet broadcast route before mutating automatic-presentation state. This avoids entering an expanded notification state and trying to undo it at the view layer.

Session notifications reuse the existing completion/attention transition detection and policies. Left-feature producers reuse the same coordinator entry point whether the event originates from `ccFlowHint` or `ProductivityProactiveEventCenter`.

The closed `NotchView` observes the coordinator and overlays each active item in its assigned half. Hover dispatches through existing `NotchViewModel` session and custom-feature presentation methods rather than adding a second navigation implementation.

## Mode transitions and conflicts

- Active to Quiet does not close a panel the user already opened. Only future automatic notifications use broadcasts.
- Quiet to Active clears active and queued broadcasts without replaying or opening them. Future notifications use existing automatic presentation.
- If a panel is already open, closed-state broadcasts are not overlaid. The event follows the existing open-panel content routing.
- If the app is hidden for fullscreen or changing displays, short-lived queued items may remain, but expired items are discarded instead of replayed.
- The left and right queues advance independently.

## Testing

Add logic tests for:

- Persisted mode defaults to Active and round-trips through settings.
- Sound playback depends on `soundEnabled`, not presentation mode.
- Quiet mode reroutes only notifications that would automatically present.
- Each side queues independently, deduplicates by target, and expires after five seconds.
- Switching to Active clears broadcasts without replaying them.
- Removed sessions and disabled features are skipped.
- Hover routing opens the correct session or left feature and removes the broadcast.

Add view-model or focused SwiftUI boundary tests for:

- Left and session broadcasts stay in their respective halves.
- One-line tail truncation is applied at rendering time.
- Both broadcasts can coexist without replacing compact pet state.
- Reduce Motion selects opacity-only transitions.

Verification should include Prototype tests, the affected root unit-test slice, a Debug build, and manual visual checks in Active/Quiet and sound on/off combinations.

## Out of scope

- Changes to the detached desktop pet notification layout.
- New notification categories or user-configurable per-category Quiet rules.
- Changes to notification sounds, sound themes, or temporary reminder-mute behavior beyond ensuring those controls remain independent.
