# Completion Quick Replies

## Goal

Let a user continue a just-completed Claude Code, Codex, or TRAE session from the Flow Island with a configurable one-click follow-up message.

This feature is separate from permission approval and `AskUserQuestion`. Those prompts keep their existing blocking Hook response UI. Completion quick replies create a new user turn after a task has completed.

## Product behavior

- Ship with three quick replies in this order: `OK`, `继续`, `允许`.
- Show quick replies on normal task-completion notifications and other completion states that represent a session ready for another user turn.
- Do not show them on error, resource-limit, or other exceptional completion notifications where a generic follow-up could be misleading.
- Show the first three configured replies as compact buttons. Put additional replies in a `更多` menu.
- Use the same quick-reply component and behavior in the docked Flow Island completion panel and the detached pet completion bubble.
- Do not add the configured replies to permission or question forms.

## Delivery behavior

The existing Hook connection cannot deliver a new turn after a completion event because the completion Hook is notification-only and has already returned. Delivery therefore follows the session's available interaction channel.

### tmux-backed sessions

1. Disable the selected action while delivery is in progress to prevent duplicate sends.
2. Send the reply to the original tmux pane through the existing `SessionMonitor.sendSessionMessage` path.
3. On success, dismiss the completion notification. The next provider Hook activity updates the session normally.
4. On failure, keep the notification open, restore the actions, and show a concise inline error with a recovery path.

### Sessions without a direct message channel

1. Copy the selected reply to the macOS pasteboard.
2. Activate the corresponding client/session through `SessionLauncher`.
3. Keep the completion notification until the existing presentation lifecycle dismisses it.
4. Show brief feedback that the reply was copied and must be pasted to send.
5. If activation fails, retain the copied reply and report that the client could not be opened.

The UI must not claim that a message was sent when it was only copied.

## Settings

Add a `快速回复` card under `集成 → 审批与提问`.

The card contains:

- An enable/disable toggle. It defaults to enabled.
- The ordered list of reply strings.
- Controls to add, rename, delete, and reorder entries.
- A short explanation that tmux sessions send directly while other sessions copy the reply and return to the client.

Validation rules:

- Trim leading and trailing whitespace before saving.
- Reject empty or whitespace-only replies.
- Reject exact duplicates after trimming.
- Preserve the user's order.
- Do not silently restore deleted defaults. The defaults apply only when no value has previously been persisted.
- Allow an empty configured list; in that state the completion notification has no reply actions even if the feature toggle is enabled.

Persist the toggle and ordered string list in `AppSettings`/`UserDefaults`, following existing settings bootstrap and publication patterns.

## UI and accessibility

- Use existing settings cards, button styles, spacing, and semantic colors rather than introducing a new visual language.
- Keep direct reply buttons compact while providing an adequate hit area.
- Give every button and menu item an accessibility label that includes the full reply text.
- Preserve keyboard navigation and visible focus behavior.
- Show progress and copy/send outcomes with text or symbols, not color alone.
- Avoid increasing the completion notification's minimum height when quick replies are disabled or unavailable.

## Components and data flow

- `AppSettings` owns `completionQuickRepliesEnabled` and `completionQuickReplies`.
- A focused settings editor view owns list editing and validation UI.
- `SessionCompletionNotificationView` owns transient sending, copied, and error feedback state and receives the shared `SessionMonitor` needed to send a follow-up.
- A small delivery helper chooses between direct tmux delivery and copy-plus-activation so the docked and detached presentation paths cannot diverge.
- `IslandOpenedContentView` passes the existing shared session monitor into the completion view.

Data flow:

1. A completion notification is presented with its live `SessionState`.
2. The view reads enabled, ordered quick replies from `AppSettings`.
3. The user selects a reply.
4. The delivery helper checks whether the session supports the existing direct tmux messaging path.
5. The helper either sends and dismisses, or copies, activates, and reports the fallback outcome.

## AskUserQuestion compatibility

- Claude Code: the current Bridge supports blocking `PreToolUse` `AskUserQuestion` events and returns answers through the waiting Hook response.
- Codex: CC FLOW can parse compatible question events and submit predefined answers when a responding Hook event is supplied, but Codex should not be described as universally providing Claude Code's native `AskUserQuestion` Hook contract. Custom free-text question input remains disabled for Codex client sessions.
- Neither provider's completion Hook is reused for quick replies.

User-facing copy should distinguish "supports compatible question events" from a guarantee that every Codex surface emits a blocking `AskUserQuestion` Hook.

## Error handling

- Direct-send failure: keep actions available and display a localized failure message.
- Clipboard failure is not expected with the general pasteboard API; activation failure still leaves the reply copied.
- Missing or stale session: do not dismiss the notification; explain that the original session is unavailable.
- Prevent concurrent quick-reply deliveries from the same notification.

## Validation

- Settings tests cover default values, persistence, trimming, duplicate rejection, deletion, and ordering.
- Delivery tests cover direct-send selection, copy/activate fallback, direct-send failure, activation failure, and duplicate-tap suppression.
- Completion-view tests cover eligibility by notification kind, first-three plus overflow behavior, disabled and empty-list states, and accessibility labels.
- Existing approval and `AskUserQuestion` tests remain unchanged and passing.
- Verify both docked and detached completion presentations use the same behavior.
- Run the focused root unit tests and a Debug app build; run the full repository regression when practical.
