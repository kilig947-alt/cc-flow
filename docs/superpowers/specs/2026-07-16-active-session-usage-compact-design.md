# Active-session Usage Compact Display

## Goal

Make the collapsed native Usage feature show the remaining allowance for the provider that owns the currently active session. The expanded Usage panel continues to show both Claude Code and Codex.

## Provider Selection

Selection uses the sessions already published by `SessionMonitor` and considers only Claude Code and Codex:

1. Filter sessions whose `phase.isActive` is true (`processing` or `compacting`).
2. If one or more are active, choose the session with the newest `lastActivity`.
3. If none are active, choose the most recently active Claude/Codex session by `lastActivity`, including waiting, idle, and ended sessions still present in the monitor.
4. If no Claude/Codex session exists, return no selected provider and retain the existing cross-provider fallback.

The selection rule is a pure helper so it can be tested without constructing SwiftUI views.

## Data Flow and Display

`NotchView`, which already observes `SessionMonitor`, derives the selected `UsageProviderID` and passes it into `UsageCompactView`.

When a provider is selected, `UsageCompactView`:

- filters the usage snapshot to that provider;
- shows that provider's lowest remaining account window as `Claude 80%` or `Codex 80%`;
- if no account window is available, shows that provider's today token total;
- if neither value is available, shows the provider name with the generic Usage fallback.

When no provider can be selected, the compact view preserves the current behavior: show the lowest remaining window across providers, then the combined today token total, then the generic Usage label.

The refresh lifecycle does not change. Session changes only switch which already-loaded provider snapshot is presented; they do not trigger extra account or transcript queries.

## Scope

- Change only the collapsed native Usage presentation and provider-selection helper.
- Do not change the expanded Usage panel, refresh intervals, account queries, token aggregation, feature ordering, or shortcut behavior.
- Add English and Simplified Chinese format strings for the provider-specific compact labels.

## Tests

Add focused tests covering:

- newest active Claude/Codex session wins;
- an active session wins over a newer non-active session;
- most recent Claude/Codex session is used when none are active;
- TRAE sessions are ignored;
- no eligible sessions returns no provider;
- provider-specific remaining and token fallback text;
- no-provider behavior retains the existing aggregate fallback.
