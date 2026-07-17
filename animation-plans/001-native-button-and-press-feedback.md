# 001 — Make ranking cards native, responsive buttons

- **Status**: DONE
- **Commit**: c743342
- **Severity**: HIGH
- **Category**: Purpose, physicality, accessibility
- **Estimated scope**: 2 files, about 80 lines

## Problem

`Sources/CodexToolbox/Popover/RankingSection.swift` previously turned a visual card into a
button with `onTapGesture` and accessibility traits. It does not inherit native
keyboard activation, focus, or press state, and has no pointer-down feedback:

```swift
.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
.onTapGesture {
    if presentation != .expanded { onExpand() }
}
```

## Target

Use a real SwiftUI `Button`. Its custom style must scale to `0.97` immediately
while pressed and return with a critically damped spring:

```swift
.scaleEffect(configuration.isPressed ? 0.97 : 1)
.animation(.spring(response: 0.14, dampingFraction: 1), value: configuration.isPressed)
```

The card must work with Return/Space, expose a descriptive accessibility label,
and retain the existing expand/collapse behavior.

## Repo conventions to follow

- Existing icon actions use real `Button` values and accessibility labels.
- Dashboard spatial changes use SwiftUI springs, not keyframes.
- Do not add a third-party motion dependency.

## Steps

1. Replace the ranking card gesture wrapper with `Button(action:label:)`.
2. Add a reusable press-feedback `ButtonStyle` using scale `0.97` and a 140ms,
   damping-1 spring.
3. Remove manually-added button accessibility traits; keep a specific label and
   hint supplied to the native control.

## Boundaries

- Do not alter ranking calculations or row content.
- Do not add sound or haptics.

## Verification

- Run `swift test` and the complete Xcode tests.
- With Full Keyboard Access enabled, tab to each ranking card and activate it
  with Space and Return.
- Hold the pointer down: scale feedback begins immediately and never overshoots.
- Done when pointer, keyboard, and VoiceOver trigger the same action.
