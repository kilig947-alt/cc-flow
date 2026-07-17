# Expanded Panel Pointer Performance and GitHub Heatmap Design

## Goal

Remove pointer-movement jank from the opened Flow Island feature panel and make the GitHub contribution heatmap use the full available card width without a large empty leading region.

## Scope

This change is limited to the docked custom-expanded panel resize affordance and the native GitHub feature view. It does not change persisted panel sizes, resize drag behavior, GitHub authentication, contribution fetching, or repository navigation.

## Pointer Performance

The opened notch currently attaches `onContinuousHover` to the full panel solely to determine whether the pointer is near either bottom corner. That callback runs for every pointer movement over the panel and adds avoidable SwiftUI event and layout work.

Remove the panel-wide continuous-hover tracker and its edge-zone state. Render both resize handles whenever a docked custom-expanded panel is open. Keep them subtle at rest and let each handle's existing local `onHover` highlight it and select the diagonal resize cursor. Existing global-coordinate drag handling, live size overrides, and per-feature size persistence remain unchanged.

This trades automatic handle hiding for predictable pointer performance and better discoverability.

## GitHub Contribution Heatmap

The current visible-week calculation divides the available width by a constant unrelated to the rendered cell pitch. It therefore selects too few contribution days. Because the grid is trailing-aligned, those days occupy only the right side of the card.

Use a fixed, readable cell size and spacing to calculate the number of whole week columns that fit in the measured width. Clamp the result to GitHub's maximum 53 weeks, take exactly that many trailing days, and lay the grid out from the leading edge. The grid must remain within the card and preserve seven day rows, contribution colors, dates, counts, and accessibility labels.

## Verification

- Moving the pointer throughout an opened GitHub panel does not drive a panel-wide continuous-hover callback.
- Both bottom resize handles remain visible but subdued; hover cursor and drag resizing still work.
- At common expanded widths, the heatmap begins near the card's leading inset and fills the available width with as many complete weeks as fit.
- Narrow widths remain safe: at least one week is rendered and no division-by-zero or negative sizing occurs.
- The app target builds, and focused tests are added for any extracted week-count calculation that can be tested without rendering SwiftUI.
