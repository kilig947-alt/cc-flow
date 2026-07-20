# Keep Closed Session Count Visible

## Goal

Keep the active/attention session count displayed immediately to the right of the mascot and ensure it is not clipped.

## Scope

- Preserve the numeric `Text` in `closedRightMascotRegion`.
- Grow the trailing region based on the number of digits in the count.
- Prevent SwiftUI from compressing the count text horizontally.
- Preserve session counting for all non-visual behavior.
- Preserve the manual-attention bell overlay.
- Do not change mascot rendering, animation, sizing, or session lifecycle behavior.

## Implementation

Keep `closedRightMascotRegion` unchanged visually. Calculate `closedTrailingWidth` from the mascot width, spacing, digit count, and trailing padding whenever the count is nonzero, while retaining the existing fallback width when there is no count.

## Verification

- Build the app target to catch SwiftUI compilation errors.
- Confirm by code inspection that the numeric session count and `BellIndicatorIcon` remain intact.
