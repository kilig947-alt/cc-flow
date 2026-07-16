# Mascot Design Launch Buttons

## Goal

Make the mascot generator entry points explicit and convenient for Codex, Claude, and TRAE Work while preserving the existing manual copy action.

## User interface

- Keep the explanatory text at the top of the "用 TRAE Work Design 生成宠物" card.
- Move launch actions to a separate row directly below the explanatory text.
- Show three equal-priority buttons in this order:
  1. `去 Codex Design 生成`
  2. `去 Claude Code Design 生成`
  3. `去 TRAE Work Design 生成`
- Keep the existing `复制提示词` button in the prompt header unchanged.
- Use consistent button styling, spacing, icons, hover behavior, and keyboard accessibility across all three launch actions.

## Interaction behavior

Every launch button performs the same two-stage action:

1. Copy the complete `designPromptTemplate` string to the general pasteboard.
2. Activate or launch the selected desktop application.

Application targets:

- Codex: activate or launch the Codex desktop application using bundle identifier `com.openai.codex`.
- Claude Code Design: activate or launch the Claude desktop application. Resolve bundle identifier `com.anthropic.claudefordesktop` first and fall back to the installed application named `Claude` when needed.
- TRAE Work Design: retain the existing `TraeSessionLauncher.activate(.traeWorkCN)` behavior.

The application is not expected to receive an automatic paste or a pre-created conversation. The prompt remains on the clipboard for the user to paste. A launch failure must not undo or prevent the clipboard copy.

## Implementation structure

- Add a small shared launcher abstraction for desktop Design targets instead of repeating application-resolution code in the SwiftUI button closures.
- Keep prompt copying in one helper so the three launch buttons and the existing standalone copy button use identical pasteboard behavior.
- Preserve the current two-second copied-state feedback for the standalone copy button.
- Provide concise failure feedback when an application cannot be found or launched.

## Validation

- Verify all three launch buttons copy the exact prompt template before attempting launch.
- Verify Codex and Claude resolution handles both already-running and installed-but-closed applications.
- Verify TRAE Work still routes to the CN/Work variant currently used by the existing button.
- Verify the standalone copy button remains present and functional.
- Build the CCFlow Debug scheme to catch SwiftUI and AppKit integration errors.
