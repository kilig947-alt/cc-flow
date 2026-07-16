# Active-session Usage Compact Implementation Plan

1. Add a pure provider selector that prioritizes the newest active Claude/Codex session and otherwise returns the most recently active eligible session.
2. Add a pure compact metric resolver for provider-specific remaining allowance, provider-specific today tokens, and the existing aggregate fallback.
3. Pass the selected provider from `NotchView` into `UsageCompactView`; localize concise provider labels and expose the actual compact value to accessibility.
4. Add focused selector/resolver tests, run the Usage/shortcut test slice, build Debug, request code review, commit, and merge into `merge_main_cc` without disturbing other work.
