# Smart Suppression Broadcast Design

## Goal

Keep Smart Suppression while guaranteeing that every eligible visual notification is delivered. Smart Suppression changes presentation intensity; it never discards a notification.

## Presentation matrix

| Presentation mode | Smart suppression | Session notification | Left-feature notification |
| --- | --- | --- | --- |
| Active | Not triggered | Open the corresponding session route | Open the corresponding feature |
| Active | Triggered | Show a five-second session broadcast | Show a five-second left-feature broadcast |
| Quiet | Either state | Show a five-second session broadcast | Show a five-second left-feature broadcast |

Explicit temporary reminder mute remains the only user notification policy that may discard eligible visual notifications. Fullscreen-hidden presentation may retain events until the Flow Island can be shown.

## Routing rules

- Smart Suppression is evaluated only when Active mode would otherwise expand the Flow Island.
- Quiet mode does not read Smart Suppression because it already uses the least intrusive presentation.
- A valid compact broadcast counts as delivered after it is accepted by `CompactBroadcastCoordinator`.
- Session and left-feature notifications use the same downgrade rule and independent broadcast queues.
- If the Flow Island is already open, Active mode routes to the corresponding content. Quiet mode does not force a content switch; the open panel remains visible and no hidden compact broadcast is consumed behind it.
- When Quiet mode receives an event while the panel is open, retain it until the panel closes, then show its compact broadcast if it has not expired. This avoids both interruption and invisible acknowledgement.

## State transitions

- Switching Active → Quiet affects future and retained undelivered events; it does not close an open panel.
- Switching Quiet → Active clears already-visible compact broadcasts as before. Undelivered events are evaluated through the Active matrix and are not silently discarded.
- Smart Suppression turning off does not replay broadcasts already delivered during suppression.

## Testing

- Active + no suppression expands session and feature routes.
- Active + suppression enqueues the correct side instead of expanding or discarding.
- Quiet always enqueues both sides regardless of terminal visibility.
- Quiet events received while the panel is open remain undelivered and appear after close.
- Temporary reminder mute still discards.
- Sound playback remains independent from presentation mode and Smart Suppression.

## Out of scope

- Removing Smart Suppression or changing terminal-visibility detection.
- Changing compact broadcast visuals, duration, truncation, or hover routing.
- Changing detached-pet notification behavior.
