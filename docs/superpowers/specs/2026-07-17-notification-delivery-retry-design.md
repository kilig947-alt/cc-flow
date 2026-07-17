# Notification Delivery Retry Design

## Goal

Restore reliable automatic Flow Island presentation in Active mode without changing Quiet mode's compact broadcasts. A notification must not be treated as delivered until its visual route has actually been presented.

## Confirmed failures

- Productivity notifications are retried indefinitely whenever any unrelated session needs permission or human input.
- Pending-session IDs are marked handled while smart suppression or fullscreen suppression blocks presentation, so the event never retries.
- Manual-attention tracking advances before presentation policy is evaluated, producing the same one-shot loss during transient suppression.
- Active mode selects the legacy routes but does not provide delivery guarantees around those routes.

## Delivery policy

### Active mode

- A left-feature event may open its feature even when another session needs attention. Session attention remains visible through its own route and must not globally block the left-feature queue.
- A new pending or manual-attention session remains pending while automatic presentation is transiently suppressed.
- The event is acknowledged only after `notchOpen`, `presentNotificationAttention`, `presentNotificationChat`, or `presentCustomExpanded` succeeds.
- When suppression clears, retained events retry automatically.

### Quiet mode

- Existing five-second left/session compact broadcasts remain unchanged.
- Enqueueing a valid compact broadcast counts as successful visual delivery and advances the producer's pending state.

### Intentional suppression

Temporary reminder mute remains an explicit discard policy. It may acknowledge/drop events while active. Smart suppression and fullscreen presentation suppression are transient policies and must retain events.

## Architecture

- Replace the session pending-ID snapshot with a small delivery tracker that separates observed IDs from delivered IDs.
- Extend manual-attention tracking with a non-consuming candidate lookup plus an explicit acknowledgement step, or equivalent state that advances only after delivery.
- Re-run retained session delivery when relevant suppression inputs change and when session snapshots refresh.
- Remove `hasPendingPermission` and `hasHumanIntervention` from the productivity presentation guard; retain inline-input, settings-popover, completion-notification, cooldown, and fullscreen route guards.
- Keep producer-specific priority: session and left-feature routes are independent rather than one globally blocking the other.

## Tests

- A pending session blocked by smart/fullscreen suppression is delivered after suppression clears.
- Manual attention is not consumed when presentation is blocked and is acknowledged after successful delivery.
- Multiple attention sessions are delivered without losing all but the first.
- Active productivity delivery is not blocked by unrelated permission or question sessions.
- Temporary reminder mute still drops notifications intentionally.
- Quiet-mode broadcasts and sound independence continue to pass their existing tests.

## Scope

This fix changes notification delivery state only. It does not alter notification visuals, detached-pet behavior, sound settings, feature enablement, or fullscreen detection.
