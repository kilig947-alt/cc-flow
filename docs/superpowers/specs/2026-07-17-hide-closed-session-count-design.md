# Hide Closed Session Count

## Goal

Remove the active/attention session count displayed immediately to the right of the mascot in the closed Flow Island.

## Scope

- Remove the numeric `Text` from `closedRightMascotRegion`.
- Remove spacing that existed only to separate the mascot from that number.
- Preserve session counting for all non-visual behavior.
- Preserve the manual-attention bell overlay.
- Do not change mascot rendering, animation, sizing, or session lifecycle behavior.

## Implementation

Keep `closedRightMascotRegion` as the existing mascot-and-bell container, but eliminate the surrounding count-oriented `HStack` and its local `activeCount`. Retain the existing trailing padding so the mascot remains inset from the Flow Island edge.

## Verification

- Build the app target to catch SwiftUI compilation errors.
- Confirm by code inspection that no numeric session count remains in `closedRightMascotRegion` and that `BellIndicatorIcon` remains intact.
