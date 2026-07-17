# 002 — Unify dashboard motion and accessibility fallbacks

- **Status**: DONE
- **Commit**: c743342
- **Severity**: HIGH
- **Category**: Easing, cohesion, accessibility
- **Estimated scope**: 3 files, about 90 lines

## Problem

`Sources/CodexToolbox/Popover/DashboardView.swift` previously used two
different bouncy `.snappy` animations, while `:184` always applies matched
geometry. There is no Reduced Motion branch:

```swift
withAnimation(.snappy(duration: 0.34, extraBounce: 0.04)) { ... }
withAnimation(.snappy(duration: 0.30, extraBounce: 0.02)) { ... }
.matchedGeometryEffect(id: metric.rawValue, in: rankingNamespace)
```

## Target

All dashboard layout and collapse changes use:

```swift
.spring(response: 0.35, dampingFraction: 1.0)
```

When `accessibilityReduceMotion` is true, remove matched geometry, scaling and
movement. Preserve comprehension with a 200ms opacity crossfade:

```swift
.easeOut(duration: 0.20)
```

## Repo conventions to follow

- Read accessibility preferences with SwiftUI environment values.
- Keep the app crisp and restrained; no bounce is appropriate for a monitoring
  dashboard.

## Steps

1. Introduce shared motion values for the dashboard spring and reduced-motion
   crossfade.
2. Branch animation selection on `accessibilityReduceMotion`.
3. Apply matched geometry only when motion is allowed.
4. Apply the same branch to module collapse/expand and settings page changes.

## Boundaries

- Do not animate scrolling or chart values continuously.
- Do not remove opacity/color feedback under Reduced Motion.

## Verification

- Run the app and rapidly expand different cards; retargeting must remain smooth.
- Enable Reduce Motion in System Settings: the same changes crossfade for about
  200ms with no translation, scaling, or geometry morph.
- Done when all dashboard state changes use one motion personality.
