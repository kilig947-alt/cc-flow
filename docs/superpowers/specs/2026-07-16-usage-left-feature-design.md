# Usage Left Feature and Per-Feature Shortcuts Design

## Summary

Add a native, system-provided Usage left feature that reports Claude Code and Codex account allowance plus local token consumption. The feature is enabled by default, inserted at the first position on first migration, and can be disabled or reordered like other left features. Disabled means inactive: no timers, account queries, app-server process, or transcript scans.

Add an optional global shortcut to every left feature. A feature shortcut opens the Flow Island directly to that feature. Duplicate shortcuts are rejected with a specific, accessible error.

## Scope

Version one supports:

- Claude Code account windows and local token consumption.
- Codex account windows/account activity and local token consumption.
- Today, seven-day, and current-session token summaries.
- One optional global shortcut for every built-in, custom HTML, and remote URL left feature.

Version one does not support TRAE variants, usage warnings/notifications, billing forecasts, or storing provider credentials.

## Decisions

- Account allowance is the primary information; local token consumption is secondary.
- The Usage feature refreshes every ten minutes while enabled.
- It refreshes immediately only when it becomes the active expanded feature. Merely opening the Island while another feature is selected does not refresh it.
- Triggering its global shortcut selects it, opens the expanded Island, and refreshes it.
- Shortcut collisions are rejected instead of overwriting or swapping an existing shortcut.
- Last successful results remain visible during refresh and partial provider failures.

## Left Feature Model and Migration

Add a parameterless `usage` case to `LeftFeatureKind` and a stable `LeftFeature.usageID`. Its default icon is the SF Symbol `chart.bar.xaxis` and its default display name is localized as “用量” / “Usage”. It renders with native SwiftUI and never creates a `WKWebView`.

Add `globalShortcut: GlobalShortcut?` to `LeftFeature`. Custom decoding treats the absent field as `nil`, preserving old persisted feature arrays.

`LeftFeatureStore` performs an idempotent `ensureBuiltinUsageFeature` migration:

1. If the fixed usage ID exists, preserve its enabled state, order, size, and shortcut.
2. Otherwise insert an enabled Usage feature at displayed index zero.
3. Renumber the remaining sort orders once.
4. Never force the feature back to index zero after the initial insertion.

Disabling a feature keeps its shortcut value but removes the system registration. Re-enabling restores registration when the shortcut remains valid.

## Usage Domain Model

Provider-specific payloads normalize into a shared immutable snapshot:

```swift
struct UsageSnapshot: Codable, Equatable, Sendable {
    var providers: [ProviderUsageSnapshot]
    var capturedAt: Date
}

struct ProviderUsageSnapshot: Codable, Equatable, Sendable, Identifiable {
    var provider: UsageProviderID
    var accountState: UsageAccountState
    var windows: [UsageWindow]
    var tokenSummary: TokenUsageSummary?
    var capturedAt: Date?
    var error: UsageProviderError?
}
```

Each window contains used percentage, remaining percentage, duration, and optional reset time. `TokenUsageSummary` contains today, trailing seven days, and current-session totals, with input, output, cache-read, and cache-write breakdowns where available.

The display layer uses locale-aware number/date formatting. Remaining percentage is derived from a clamped used percentage when the source only reports usage.

## Provider Architecture

`UsageProvider` is an async protocol whose implementations return one provider result without mutating UI state. `UsageService` owns lifecycle, caching, refresh coalescing, and publication on the main actor.

### Claude Code

The primary account source is the existing managed Claude `statusLine` input. Extend its atomic snapshot to retain:

- `rate_limits.five_hour` and `rate_limits.seven_day`;
- `context_window` token fields;
- `cost` when present;
- session ID and capture time.

The account snapshot is absent before Claude’s first API response and can become stale when no Claude session is active. The UI distinguishes missing, live, and stale states.

Local token totals are aggregated from `~/.claude/projects/**/*.jsonl`. Assistant usage rows must be deduplicated by message ID across files because tool-use content can repeat the same logical message. Synthetic messages are excluded.

The application does not read Claude OAuth tokens or call Anthropic’s private OAuth usage endpoint.

### Codex

The primary account source is a managed `codex app-server` connection:

- `account/rateLimits/read` provides account windows and reset timestamps.
- `account/usage/read` provides account token activity when supported.
- `account/rateLimits/updated` sparse notifications merge into the latest full snapshot.

The process has bounded startup/request timeouts and is terminated when Usage is disabled or the app exits. The app-server remains the credential owner; CC FLOW does not read or persist Codex auth tokens.

Codex rollout JSONL is a fallback for local token consumption and, when present, account-window data. `token_count.info.total_token_usage` is cumulative per session, so aggregation uses nonnegative deltas between adjacent events rather than summing cumulative totals. A null `rate_limits` value does not invalidate token totals.

### Local Scan Performance

The transcript aggregator follows the proven MioIsland approach:

- Filter candidates by modification date and filename before reading.
- Cache size/mtime fingerprints and skip unchanged data.
- Read large JSONL files with memory-mapped `Data` and line iteration.
- Perform parsing off the main actor.
- Treat malformed lines as isolated input errors rather than failing the provider.

Seven-day aggregation uses local calendar day boundaries. Current-session totals use the active session IDs/transcript paths already known by `SessionStore`; when no matching active session exists, that field is unavailable rather than zero.

## Refresh Lifecycle

`UsageService` exposes `start`, `stop`, and `refresh(reason:)`.

- `start` is called only while the fixed Usage feature is enabled. It schedules a ten-minute refresh and may refresh immediately if no fresh cache exists.
- `stop` cancels the timer, in-flight tasks, provider subprocesses, and transcript scanning. It keeps the last non-sensitive display cache for the next enable.
- `refresh(.becameActive)` runs when `expandedActiveFeatureID` changes to the Usage ID.
- `refresh(.shortcut)` runs after a shortcut selects and opens the Usage feature.
- Concurrent refresh requests coalesce into one task.
- EnergyGovernor may defer passive refresh while sleeping, locked, or in a suspended low-power tier. On resume, stale enabled data refreshes once.

Only normalized non-sensitive snapshots and timestamps are persisted. OAuth tokens, JWTs, API keys, authorization headers, and raw provider responses are never cached.

## Expanded Usage UI

`UsageExpandedView` uses a compact native dashboard matching the existing macOS settings and Island visual language.

- Header: “用量”, last update time, and a labeled refresh button.
- Provider cards: Claude Code then Codex, each with plan/account state, allowance bars, remaining percentage, and reset time.
- Secondary section: Today, 7 days, and current session token totals with optional input/output/cache disclosure.
- Loading: preserve old data, show an inline progress indicator, and announce the update accessibly.
- Empty/unauthenticated: identify the provider and give a concrete recovery action such as starting/signing in to its CLI.
- Error: retain stale data, show an inline message and Retry action. One provider’s failure never hides the other provider.

Bars include textual percentages and labels; color is never the only signal. Controls retain native focus rings and at least 44-point interaction areas. Motion is limited to native progress/content transitions and respects Reduce Motion.

The compact Island slot shows a concise worst-window remaining value across available providers plus a short provider label. When no account window is available it falls back to today’s token total, then to a neutral Usage label.

## Per-Feature Shortcut Editing

All feature edit sheets expose the existing shortcut recorder pattern: Record, Clear, and Reset. Feature shortcuts default to `nil`, so Reset clears them.

Built-in features without other editable fields receive a lightweight edit sheet containing shortcut and applicable expanded-size controls. The feature list stays visually compact; shortcuts are not rendered inline in every row.

Shortcut validation checks:

- fixed `GlobalShortcutAction` values;
- enabled and disabled left features;
- the current feature’s prior value is excluded during replacement.

On collision, the new value is not persisted and the recorder shows “该快捷键已被『…』使用” with an accessibility announcement. A disabled feature still owns its configured combination, preventing latent collisions when re-enabled.

## Shortcut Registration and Routing

Refactor `GlobalShortcutManager` to register a common target enum:

```swift
enum GlobalShortcutTarget: Hashable {
    case action(GlobalShortcutAction)
    case leftFeature(String)
}
```

Registrations combine fixed actions with enabled feature shortcuts. Carbon IDs are runtime identifiers mapped back to targets; they are not persisted. Registration failures are published for settings diagnostics and do not erase configuration.

A left-feature shortcut posts a typed notification or calls an injected router with the feature ID. The router:

1. Confirms that the feature still exists and is enabled.
2. Sets `expandedActiveFeatureID`.
3. Opens the docked Island through the shared `.customExpanded` presentation path.
4. Lets selection observation trigger Usage refresh when applicable.

This routing must use the shared docked/detached presentation orchestration and must not recreate detached-only priorities.

## Error Handling

- Missing CLI/account: provider card is unavailable with recovery guidance.
- Statusline not yet populated: show waiting/stale state, not zero allowance.
- App-server missing or incompatible: Codex account data is unavailable; local rollout totals can still render.
- Timeout or process exit: preserve last success and expose Retry.
- Malformed JSONL: skip the row, continue aggregation, and record bounded diagnostics without transcript content.
- System shortcut registration failure: show an inline registration error; keep the configured shortcut for later retry.

## Testing

Add deterministic unit tests for:

- Usage feature insertion, default enabled state, first-position migration, idempotency, and user reorder preservation.
- Decoding old `LeftFeature` payloads without `globalShortcut`.
- Enable/disable lifecycle and ten-minute scheduling with an injected clock/scheduler.
- Active-selection refresh, shortcut refresh, coalescing, cancellation, and stale-cache fallback.
- Claude statusline decoding, missing fields, staleness, and message-ID deduplication.
- Codex app-server response/update merging and timeout/exit behavior.
- Codex cumulative token delta calculation, null rate limits, session boundaries, and malformed lines.
- Today/seven-day/current-session aggregation and file fingerprint skipping.
- Shortcut persistence, collision naming, disabled-feature ownership, registration, and feature routing.
- View states for loading, success, partial failure, stale, unauthenticated, and retry.

Verification commands:

```bash
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug CODE_SIGNING_ALLOWED=NO test -only-testing:CCFlowTests
xcodebuild -project CCFlow.xcodeproj -scheme CCFlow -configuration Debug build
```

The implementation will compare focused test results against the recorded existing baseline failures. At design time the copied upstream work-in-progress compiles and the FlowIsland provider summary tests pass, while the full suite has unrelated existing failures/crashes in launch settings, mascot migration, compact-height, media, and window-geometry tests.

## Reference Findings

MioIsland was reviewed as requested. Reused concepts are Claude message-ID deduplication, Codex cumulative-delta aggregation, mtime/size fingerprinting, and memory-mapped JSONL reads. Its direct Claude Keychain OAuth call and rollout-first Codex allowance lookup are deliberately not adopted as primary sources because the selected design avoids handling provider credentials and prefers documented app/status surfaces.

## Out of Scope

- TRAE, TRAE CN, TRAE WORK, and TRAE WORK CN usage.
- Direct private provider HTTP APIs and credential extraction.
- Usage-limit notifications or sound alerts.
- Currency billing forecasts and model pricing tables.
- Cross-device or cloud synchronization of usage history.
