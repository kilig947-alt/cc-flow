# Productivity Notification Queue and Resource Favicon Design

## Goal

Ensure download, browser-resource, mail, and calendar reminder events reliably open the matching Flow Island feature without interrupting critical interaction, and show saved links with the same favicon pipeline used by left-side web features.

## Notification Queue

- `ProductivityProactiveEventCenter` owns an ordered pending-event queue instead of a single last event.
- Events for the same feature continue to aggregate for five seconds before entering the queue.
- Download start/completion, newly saved browser resources, new Mail messages, and actionable Calendar reminders all use this queue.
- The Flow Island consumes an event only after the corresponding feature is selected and the expanded panel is actually presented.
- While inline text input, settings, permission prompts, or human-intervention UI is active, the event remains queued and presentation is retried after the blocker clears.
- Muted events and events targeting disabled features are discarded. They are not replayed after unmuting or re-enabling.
- Full-screen presentation suppression leaves an event queued until automatic presentation becomes safe.

## Calendar Integration

- Calendar keeps its existing 30-minute reminder cadence for overdue and today-due incomplete reminders.
- When the cadence permits a prompt, Calendar publishes a `calendarReminderDue` event targeting the Calendar feature.
- The separate reminder prompt token and its early-consumption path are removed so Calendar follows the same delivery rules as the other productivity features.
- Completing the reminder in CC FLOW continues to mark the corresponding macOS Reminders item complete.

## Browser Resource Favicons

- `BrowserResource` stores an optional `iconID`. Missing values remain compatible with existing persisted records.
- Saving a new resource starts `FaviconFetcher.fetch(for:)`. Existing records without an icon are backfilled after loading.
- Concurrent fetches for the same URL are deduplicated. Results update every matching persisted resource and reuse the existing `img:favicon-*` disk cache.
- Browser-resource rows render the icon with `FeatureIconView`; unavailable or invalid favicons fall back to the existing link symbol.
- Removing or re-saving a resource does not delete the shared favicon cache.

## Presentation Contract

- Notification presentation reports success or failure. A full-screen suppression failure does not consume the queued event.
- A successful presentation selects the target left feature, opens the expanded Flow Island with notification reason, then removes the event from the queue.
- Queue retry work is single-instance and stops when the queue is empty.

## Verification

- Unit tests cover queue ordering, consume-after-success behavior, aggregation, muted/disabled discard policy helpers, Calendar event publication, and decoding old Browser Resource records without `iconID`.
- Focused productivity tests verify download, mail, Calendar, browser-resource, File Watch, and favicon model behavior.
- A Debug build validates SwiftUI presentation and `FeatureIconView` integration.
