# Task Quota Attribution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the misleading account-wide proportional allocation with a per-task quota estimate derived from rate-limit snapshots embedded in local Codex rollout events.

**Architecture:** Extend the incremental usage ledger with sanitized quota observations captured beside each unique `token_count` increment. A pure estimator merges observations chronologically, ignores percentage jumps after inactive gaps, attributes clean percentage buckets across locally active root tasks, and uses the median observed Token-per-percentage rate to estimate rounded edge buckets. The UI shows these estimates beside local Token counts while keeping the authoritative all-device account percentage separate.

**Tech Stack:** Swift 6, Foundation JSON parsing, SwiftUI, XCTest, the existing versioned local usage ledger.

---

### Task 1: Persist sanitized rollout quota observations

**Files:**
- Modify: `Sources/CodexToolboxCore/Usage/UsageLedgerStore.swift`
- Modify: `Sources/CodexToolboxCore/Usage/LocalCodexUsageReader.swift`
- Test: `Tests/CodexToolboxTests/LocalCodexUsageReaderTests.swift`

**Step 1: Write the failing parser test**

Create rollout fixtures whose `token_count` payload contains `rate_limits.primary` and `secondary`. Assert that the resulting history contains only timestamp, root task ID, Token increment, duration, used percentage, and reset time. Assert that opaque limit IDs, plan details, and credit balances never appear in the saved ledger.

**Step 2: Run the focused test and confirm failure**

Run:

```bash
swift test --filter LocalCodexUsageReaderTests
```

Expected: compilation or assertion failure because quota observations are not modeled yet.

**Step 3: Add backward-compatible ledger storage**

Add a compact `ThreadQuotaUsageObservation` array to every thread entry. Bump the usage ledger to schema 2; when loading schema 1, preserve historical daily totals and clear checkpoints only for threads that already contributed Token today, so the visible task list is backfilled without rescanning the entire archive. Decode missing observation arrays as empty and continue preserving unreadable historical tasks; older threads keep their offsets and begin sampling if new events arrive later.

**Step 4: Parse only sanitized window fields**

For each unique cumulative Token event, parse both `primary` and `secondary` windows using only:

```swift
AccountQuotaWindow(
    durationMinutes: windowMinutes,
    usedPercent: usedPercent,
    resetsAt: resetDate
)
```

Never persist `limit_id`, `plan_type`, credit balances, or other account fields.

**Step 5: Run the focused test**

Expected: parser, incremental resume, truncation, migration, and privacy assertions pass.

### Task 2: Implement the hybrid estimator

**Files:**
- Modify: `Sources/CodexToolboxCore/Domain/UsageModels.swift`
- Test: `Tests/CodexToolboxTests/LocalCodexUsageReaderTests.swift`

**Step 1: Write failing estimator tests**

Cover these cases:

- a continuous task crossing five percentage boundaries estimates about five percent;
- a remote jump after a gap of more than 15 minutes is not attributed to the next local task;
- a small task inside a rounded one-percent bucket receives a proportional fractional estimate;
- a task with no current boundary uses the median current-window calibration rate;
- estimates for all local tasks never sum above the authoritative account percentage;
- mismatched reset cycles and expired windows produce no result.

**Step 2: Add public estimate models**

Add `LocalQuotaUsageObservation`, `TaskQuotaEstimate`, and `QuotaEstimateConfidence`. Extend `UsageHistory` with a backward-compatible observation array that defaults to empty when decoding older data.

**Step 3: Implement chronological bucket attribution**

For each account window:

1. match observations by duration and reset time with a small timestamp tolerance;
2. split activity after gaps longer than 15 minutes;
3. ignore account percentage jumps at a new segment baseline;
4. accumulate local Token increments until the next positive percentage step;
5. distribute that step among active root tasks by their Token increments;
6. use the median clean Token-per-percentage rate for uncovered leading/trailing tokens;
7. discard implausible/non-finite samples and scale the final local total so it cannot exceed account usage.

**Step 4: Assign confidence**

- Medium: the current window has at least ten clean observed percentage points, two
  task-specific buckets, and at least 50% direct Token coverage.
- Low: the current span is shorter than ten percentage points, or only historical
  same-duration calibration is available.

**Step 5: Run focused estimator tests**

Expected: every attribution, gap, rounding, cap, and confidence test passes.

### Task 3: Integrate estimates into the Token card

**Files:**
- Modify: `Sources/CodexToolbox/Popover/TokenUsageModuleView.swift`
- Modify: `Sources/CodexToolbox/App/DemoDashboardData.swift`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Step 1: Add demo observations**

Create deterministic weekly and five-hour quota observations so the demo dashboard exercises medium-, low-, and sub-one-percent estimates.

**Step 2: Render task and remainder estimates**

Render values such as:

```text
14,502,211 · 周≈5.0%
```

Sum hidden-task estimates for “其余任务”. If no defensible estimate exists, show only the raw Token number.

**Step 3: Keep account totals separate**

The footnote must state that task values come from local per-turn snapshot estimates and that account totals include every device. Expired windows remain hidden.

**Step 4: Document the corrected behavior**

Update user-facing documentation and the design note to describe the snapshot estimator, inactive-gap protection, confidence limits, and multi-device concurrency caveat.

### Task 4: Verify with synthetic and real data

**Files:**
- Modify if needed: implementation and tests above

**Step 1: Run formatting and focused tests**

```bash
git diff --check
swift test --filter LocalCodexUsageReaderTests
```

Expected: no whitespace errors; focused tests pass.

**Step 2: Run all package checks**

```bash
swift test
swift run CoreVerification
```

Expected: all tests and the verification executable pass.

**Step 3: Run the complete Xcode suite**

```bash
xcodebuild -project CodexToolbox.xcodeproj -scheme CodexToolbox \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Expected: `TEST SUCCEEDED` for both architectures.

**Step 4: Replay the current local ledger**

Run the estimator against the user's sanitized local observations. Confirm that the roughly 14.7M-Token task tracks its observed 12%→17% interval instead of inheriting the later 33% account total.

**Step 5: Inspect the real popover**

Launch the debug demo with `--demo-dashboard --show-dashboard`, inspect the Token card at its production width, and fix any clipping or wrapping before delivery.
