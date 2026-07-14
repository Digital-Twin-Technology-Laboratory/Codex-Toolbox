# Release Packaging Repair Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore the guided DMG installer and produce an ad-hoc-signed Hardened Runtime application that launches successfully.

**Architecture:** Link `ShowCodexIQCore` statically into the Xcode application, centralize Finder DMG construction in one script shared by both builders, and add a real launch smoke test to DMG verification. Release the result as `0.1.0-beta.3` without rewriting beta.2 history.

**Tech Stack:** Swift 6, SwiftUI/AppKit, XcodeGen, Xcode 27, Bash, `codesign`, `diskutil`, Finder AppleScript, GitHub CLI.

---

### Task 1: Make the archived application self-contained

**Files:**
- Modify: `project.yml`
- Regenerate: `ShowCodexIQ.xcodeproj/project.pbxproj`

**Step 1: Record the failing invariant**

Run:

```bash
otool -L "/Applications/Show Codex IQ.app/Contents/MacOS/Show Codex IQ" | rg ShowCodexIQCore
```

Expected before the fix: the executable references `@rpath/ShowCodexIQCore.framework`.

**Step 2: Change the core product**

Change the XcodeGen target type from `framework` to `library.static`, keeping `DEFINES_MODULE = YES` so the app and tests can continue importing `ShowCodexIQCore`.

**Step 3: Regenerate and build**

Run:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project ShowCodexIQ.xcodeproj -scheme ShowCodexIQ \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds and the application executable has no dynamic `ShowCodexIQCore` dependency.

### Task 2: Centralize the guided DMG layout

**Files:**
- Create: `scripts/package_dmg.sh`
- Modify: `scripts/build_dmg.sh`
- Modify: `scripts/build_portable_dmg.sh`

**Step 1: Extract packaging behavior**

Create a script accepting an app path, output DMG path, and volume name. It must stage the app, Applications symlink, first-open guide, and `.background/ShowCodexIQ-dmg-background.png`; create a writable APFS image; ask Finder to persist the background and icon positions; require `.DS_Store`; and compress the final image with a SHA-256 sidecar.

**Step 2: Route both builders through it**

Remove their duplicated plain/styled DMG creation blocks and call the shared script after each builder has produced and signed its app.

**Step 3: Validate shell syntax**

Run:

```bash
bash -n scripts/package_dmg.sh scripts/build_dmg.sh scripts/build_portable_dmg.sh
```

Expected: no output and exit status 0.

### Task 3: Add release-blocking runtime checks

**Files:**
- Modify: `scripts/verify_dmg.sh`

**Step 1: Add structural assertions**

Require `.background/ShowCodexIQ-dmg-background.png` and `.DS_Store`, and fail if `otool -L` reports a dynamic `ShowCodexIQCore` dependency.

**Step 2: Add a launch smoke test**

Start the mounted executable with `CFFIXED_USER_HOME` pointing to a temporary directory, capture output, and require it to remain alive for three seconds. Always terminate the smoke process and detach the image in the cleanup trap.

**Step 3: Validate the expected failure**

Run the verifier against the beta.2 DMG. Expected: fail because the guided layout is absent and/or the Core dependency is dynamic.

### Task 4: Prepare beta.3 metadata

**Files:**
- Modify: `Sources/ShowCodexIQ/Config/Version.xcconfig`
- Modify: `CHANGELOG.md`
- Modify: `README.md`
- Modify: `docs/releasing.md`

Set the full version to `0.1.0-beta.3`, retain marketing version `0.1.0`, increment build number to 3, document both fixes, and point installation examples at the new artifact.

### Task 5: Verify, package, and release

**Files:**
- Generated: `dist/Show-Codex-IQ-0.1.0-beta.3-universal.dmg`
- Generated: corresponding `.sha256`

Run CoreVerification, all Swift tests from a `/tmp` scratch path, full Xcode tests, `scripts/build_dmg.sh`, and `scripts/verify_dmg.sh`. Visually inspect the mounted Finder window. Then commit, create annotated tag `v0.1.0-beta.3`, push main and the tag, publish a GitHub pre-release with both assets, add a warning to beta.2, and wait for CI success.
