# Multi-provider compact usage design

## Goal

Ensure the closed Flow Island shows every provider that currently has a real remaining-usage percentage, even when there is no active or historical Claude Code/Codex session. Replace the Codex brand asset with the supplied transparent PNG.

## Confirmed behavior

- Read compact usage directly from `UsageService.snapshot`; session activity does not gate visibility.
- Evaluate Claude Code and Codex independently.
- Render one compact item per provider that has at least one usage window.
- Each item contains only the provider brand icon and the rounded remaining percentage.
- When both providers have data, render both items horizontally in stable provider order: Claude Code, then Codex.
- When only one provider has data, render only that provider.
- When neither provider has percentage data, render no usage content.
- Do not render aggregate percentages, token counts, provider names, placeholders, or generic status icons.
- Preserve a combined VoiceOver label such as “Codex account usage: 44% remaining.”

## Presentation

- Use a compact horizontal stack with 12 pt between provider items and 5 pt between each icon and percentage.
- Render brand images in original color at 14 × 14 pt with aspect-fit scaling.
- Render percentages with the existing 11 pt semibold rounded font and monospaced digits.
- Keep the view lifecycle stable when the visible item list is empty so `UsageService.start()` still runs.
- Use `/Users/fha0020260421001/Downloads/codex-color.png` as the Codex/OpenAI image asset. Preserve its alpha channel and original proportions.

## Data flow

1. `UsageCompactView` observes `UsageService.snapshot`.
2. A pure presentation resolver walks `UsageProviderID.allCases` in stable order.
3. For each provider, the resolver finds the corresponding snapshot and its minimum remaining percentage across available windows.
4. The resolver returns zero, one, or two `UsageCompactBrandPresentation` values.
5. SwiftUI renders the returned items without consulting `SessionMonitor` or `UsageCompactProviderSelector`.

The expanded account-usage screen and refresh/loading behavior remain unchanged.

## Error and edge handling

- Clamp and round each percentage to `0...100` before display.
- A provider with token totals but no usage window remains hidden.
- Missing, stale, or unavailable providers remain hidden unless their snapshot still contains a retained valid usage window.
- A refresh indicator may appear after the provider items, but it must not create provider or aggregate placeholder content.

## Tests

- Both Claude Code and Codex percentages resolve and retain stable order without session input.
- A single provider percentage produces one item.
- Providers without windows are omitted.
- Empty data produces an empty presentation list.
- Percentages are rounded and clamped.
- Usage provider asset mappings point to the expected bundled images.
- Asset-catalog compilation, focused unit tests, and a Debug app build succeed.

## Out of scope

- Changing the expanded usage screen.
- Selecting a “current” provider from active sessions.
- Rotating or aggregating provider percentages.
- Showing token counts in the closed Flow Island.
