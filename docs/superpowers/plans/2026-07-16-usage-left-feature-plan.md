# Usage Left Feature Implementation Plan

1. Extend `LeftFeatureKind` and `LeftFeature` with the built-in Usage case, stable ID, optional shortcut, compatible Codable behavior, display metadata, and store mutations. Add idempotent first-position migration and lifecycle notifications.
2. Add normalized usage models, Claude statusline snapshot decoding, Codex rollout parsing, and local Claude/Codex token aggregation with message deduplication, cumulative deltas, mtime filtering, and mapped reads.
3. Add `UsageService` with injected providers/scheduler seams, ten-minute passive refresh, active refresh, request coalescing, cache persistence, EnergyGovernor-aware lifecycle, and clean stop behavior.
4. Add native compact and expanded SwiftUI Usage views and route the new kind through `NotchView` and `LeftFeatureContainerView`.
5. Generalize shortcut recording and registration to support dynamic left-feature targets, collision validation, persistence, diagnostics, and direct `.customExpanded` routing.
6. Integrate shortcut editing into existing feature edit sheets/rows without widening the dense feature list.
7. Add focused model, parser, lifecycle, shortcut, and routing tests. Run focused tests first, then Debug build and the full unit suite while comparing with the recorded baseline failures.
8. Review and commit only feature-owned changes. Keep the synchronized `IslandPresentationCoordinator.swift` and `FlowIslandProviderSummaryTests.swift` edits outside feature commits. Before merging, re-check the dirty `merge_main_cc` workspace, merge the feature branch without overwriting local edits, and verify the original dirty diff remains intact.
