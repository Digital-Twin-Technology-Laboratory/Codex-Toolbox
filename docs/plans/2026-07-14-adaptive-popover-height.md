# Adaptive Popover Height Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the large blank region below the ranking cards when the trend chart is disabled.

**Architecture:** Define one shared app-level popover size policy, consume it from both the SwiftUI dashboard frame and the AppKit popover controller, and react to setting changes. Preserve the current chart-visible size and use a compact chart-hidden height.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSPopover`, Observation, XcodeGen, XCTest, Bash, GitHub CLI.

---

### Task 1: Centralize dashboard dimensions

**Files:**
- Create: `Sources/ShowCodexIQ/Popover/DashboardLayout.swift`
- Modify: `Sources/ShowCodexIQ/Popover/DashboardView.swift`

**Step 1:** Add width, chart-visible height, and chart-hidden height constants plus helpers returning the current SwiftUI height and `NSSize`.

**Step 2:** Replace the fixed dashboard frame with the shared width and height derived from `appModel.settings.showsTrendChart`.

**Step 3:** Generate the Xcode project and build. Expected: successful compilation with no remaining fixed `DashboardView` height.

### Task 2: Resize the AppKit popover when settings change

**Files:**
- Modify: `Sources/ShowCodexIQ/MenuBar/StatusItemController.swift`

**Step 1:** Retain the `AppModel` in the controller.

**Step 2:** Add an idempotent `updatePopoverSize()` using `DashboardLayout`.

**Step 3:** Call it during configuration, from the existing settings-change observer, and immediately before showing the popover.

**Step 4:** Build again. Expected: no warnings or errors introduced by the AppKit/SwiftUI size synchronization.

### Task 3: Prepare and verify beta.4

**Files:**
- Modify: `Sources/ShowCodexIQ/Config/Version.xcconfig`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

**Step 1:** Set release version to `0.1.0-beta.4` and build number to 4; document the adaptive-height fix and update artifact examples.

**Step 2:** Run CoreVerification, Swift tests, Xcode tests, shell syntax checks, and `git diff --check`.

**Step 3:** Launch the app with the chart disabled and enabled. Expected: compact height with no large blank area when disabled, existing full height when enabled.

### Task 4: Package and publish

**Files:**
- Generate: `dist/Show-Codex-IQ-0.1.0-beta.4-universal.dmg`
- Generate: `dist/Show-Codex-IQ-0.1.0-beta.4-universal.dmg.sha256`

**Step 1:** Build and verify the DMG, including the three-second launch smoke test and Finder layout.

**Step 2:** Commit, create annotated tag `v0.1.0-beta.4`, push main and tags, and publish a GitHub pre-release with both assets and update notes.

**Step 3:** Confirm uploaded asset digests and wait for GitHub Actions CI success.
