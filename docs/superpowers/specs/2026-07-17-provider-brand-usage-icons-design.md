# Provider Brand Usage Icons Design

## Goal

Replace generic Claude Code and Codex placeholders with the supplied brand artwork, and simplify the compact usage presentation to a brand icon plus an available percentage.

## Supplied Assets

- `/Users/fha0020260421001/Downloads/claude-code.png` represents Claude Code.
- `/Users/fha0020260421001/Downloads/openai.png` represents Codex/OpenAI.
- Both images are 28×28 PNG files and will be copied into dedicated image sets in `CCFlow/Assets.xcassets`.
- The assets retain their supplied colors and proportions. SwiftUI must not recolor or stretch them.

## Hooks Settings

- `HookManagementIcon` uses the bundled Claude Code image for the Claude Code managed-hook profile.
- `HookManagementIcon` uses the bundled OpenAI image for the Codex managed-hook profile.
- The existing client title, subtitle, status, and actions remain visible and unchanged.
- Other managed-hook profiles continue using their existing bundled-logo, application-icon, or SF Symbol fallback behavior.

## Compact Usage Presentation

- Remove the generic `chart.bar.xaxis` usage symbol.
- Remove the visible provider name and all generic placeholder text, including `Claude`, `Codex`, and `用量`.
- When a single provider is selected and its remaining percentage is available, render:
  - the corresponding brand icon;
  - the rounded remaining percentage, such as `48%`.
- Do not render an aggregate state when no single provider is selected.
- Render no compact usage content when the selected provider has no remaining-percentage value.
- Token-count fallbacks and provider-only placeholders are not shown in compact mode.
- The expanded usage view and its data remain unchanged.

## Layout and Accessibility

- Use a small fixed icon size aligned with the percentage baseline so the compact island does not change height.
- Use monospaced digits for the percentage to avoid width jitter during refreshes.
- Expose a combined accessibility label such as “Codex account usage: 48 percent remaining”; decorative image content is hidden from separate VoiceOver traversal.
- Preserve the existing refresh indicator only when compact content is otherwise visible.

## Data Flow

- Continue using `UsageCompactProviderSelector` to identify a single Claude or Codex provider.
- Continue using `UsageCompactMetricResolver` to read that provider's remaining percentage.
- `UsageCompactView` filters all other metric cases to an empty compact presentation; no aggregate percentage is calculated for display.

## Testing

- Verify Claude remaining usage resolves to the Claude image plus percentage without provider text.
- Verify Codex remaining usage resolves to the OpenAI image plus percentage without provider text.
- Verify aggregate, token-only, provider-only, and generic metrics produce no compact content.
- Verify Hooks settings resolve the supplied assets for Claude Code and Codex while leaving other profiles unchanged.
- Run the focused usage tests and a Debug build after implementation.
