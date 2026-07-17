# Show Codex IQ — judge quickstart

Show Codex IQ is a native macOS menu-bar app that turns Codex benchmark snapshots into quality, cost, latency, and personalized overall rankings.

> **Independent project:** Show Codex IQ is not affiliated with OpenAI or Codex Radar. The current beta reads a Codex Radar public snapshot and displays permanent attribution. Live-data use must remain subject to the data provider's permission and terms.

## Fastest test path

### Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac
- Network access to `https://codexradar.com/current.json` for a fresh snapshot

### Install the packaged app

1. Open the [`v0.1.0-beta.5` release](https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox/releases/tag/v0.1.0-beta.5).
2. Download the Universal DMG and matching `.sha256` file.
3. Optionally verify it with:

   ```bash
   shasum -a 256 -c Show-Codex-IQ-0.1.0-beta.5-universal.dmg.sha256
   ```

4. Open the DMG and drag **Show Codex IQ** into **Applications**.
5. Launch it from Applications. It appears only in the menu bar, not the Dock.

The current beta is ad-hoc signed because the maintainer does not yet have a paid Apple Developer Program certificate. If macOS displays an unidentified-developer warning, first attempt to open the app, then use **System Settings → Privacy & Security → Open Anyway**. Do not bypass a warning that explicitly reports malware or says the app will damage the computer.

### Five-minute feature tour

1. Read the top two choices directly from the two-line menu-bar item.
2. Click it to open the four ranking cards: IQ, cost, latency, and overall.
3. Expand one card from the top three to the top five.
4. Use the refresh button and inspect data freshness in the header.
5. Open Settings and change the menu-bar metric.
6. Drag both handles in the three-part weight control and confirm the three values still total 100%.
7. Toggle trend charts and observe the popover height adapt.
8. Add a menu-bar-only alias for a long model name.

No account, API key, database, or test credentials are required. After a successful load, the app keeps the last snapshot available if a later request fails.

## Build and test from source

```bash
brew install xcodegen
xcodegen generate
open ShowCodexIQ.xcodeproj
```

Core verification:

```bash
swift run CoreVerification
swift test
```

Release-package verification:

```bash
bash scripts/verify_dmg.sh dist/Show-Codex-IQ-0.1.0-beta.5-universal.dmg
```

The verifier checks the checksum, signature, app layout, static core linkage, both `arm64` and `x86_64`, and actual launch behavior with trend charts enabled and disabled.

## Architecture at a glance

```text
Codex Radar snapshot
        │
URLSessionRadarClient ── ETag / Last-Modified / 200 / 304
        │
RadarRepository actor ── single-flight refresh + stale-data policy
        │
SnapshotStore ────────── atomic last-success snapshot + local cost history
        │
RankingEngine ────────── IQ / cost / latency / weighted percentile ranking
        │
AppModel ─────────────── main-actor UI state
        ├── NSStatusItem + NSHostingView: compact two-line menu bar
        └── SwiftUI + Swift Charts: popover, trends, and settings
```

The ranking engine uses deterministic tie-breakers, average ranks for ties, and explicit missing-metric rules. Weight changes are local computations and do not cause a new network request.

## How Codex and GPT‑5.6 were used

An early working prototype existed before the OpenAI Build Week submission period. The repository documents this six-commit baseline separately. Only the substantial extensions made after the official start are presented as eligible Build Week work.

**Primary in-period `/feedback` Session ID:** `019f60dc-d23e-7ad2-84a2-a739947f1277`

The primary in-period task used `gpt-5.6-sol` and covers the custom three-way weight control and related product/release work. Follow-up Codex tasks handled installed-app launch repair, adaptive menu-bar sizing, model aliases, adaptive popover height, release automation, and documentation.

### Submission-period scope

- **Pre-period baseline:** six commits through `fb4219f` — scaffold, initial ranking/cache core, first menu-bar UI, and early packaging.
- **In-period extension:** nine commits after that baseline — 87 changed files, 2,576 insertions, and 465 deletions.
- **Eligible product work:** custom three-way weighting, trend visibility and adaptive popover behavior, compact adaptive menu-bar width, model aliases, and public release UX/documentation.
- **Eligible engineering work:** static-link launch repair, unified DMG packaging, GitHub Actions updates, checksum/signature/architecture checks, installer-layout checks, and real packaged-app smoke tests.

The original prototype task ID is retained in local history only to make the baseline auditable; it is not used as the in-period `/feedback` ID in the submission.

### In-period Codex task evidence

| Session ID | UTC window | Main contribution |
| --- | --- | --- |
| `019f60b6-fb95-7851-8613-d10523900856` | July 14, 13:00–13:58 | Open-source release structure, README/release UX, screenshots, and CI follow-up |
| `019f60dc-d23e-7ad2-84a2-a739947f1277` | July 14, 13:41–14:27 | Three-way weight control, trend visibility, product iteration, and release work |
| `019f60fb-a58c-7891-bbcd-571d9c91010e` | July 14, 14:15–15:10 | Installed-app launch diagnosis, static linking, DMG layout repair, and beta fixes |
| `019f617b-86eb-7fe2-9746-3b44e00059eb` | July 14, 16:35–17:47 | Compact adaptive menu bar, model aliases, adaptive popover height, and beta.5 |

Each task used `gpt-5.6-sol` and occurred after the official submission window opened.

Codex accelerated:

- translating the product brief into explicit data, ranking, cache, and UI boundaries;
- implementing and testing tolerant decoding, deterministic ranking, refresh scheduling, and persistent settings;
- bridging SwiftUI with AppKit for reliable menu-bar rendering;
- diagnosing ad-hoc signing and library-validation failures from real launch evidence;
- turning each release lesson into automated DMG checks.

Human decisions included:

- choosing the recurring model-selection problem and target audience;
- requiring a two-row, space-efficient menu-bar surface;
- making the quality/cost/latency trade-off user-controlled;
- defining failure invariants such as preserving the last successful ranking;
- reviewing screenshots and installed builds, then accepting or rejecting each iteration.

## Data, privacy, and scope

- The app requests only the configured benchmark snapshot endpoint.
- Conditional HTTP requests and a minimum refresh interval reduce load.
- The UI permanently attributes Codex Radar as the data source.
- Local storage contains the last snapshot, cache validators, preferences, and locally accumulated cost history.
- The app contains no analytics SDK, advertising, account system, or personal-data collection.
- Source code is MIT licensed; third-party data remains governed by its provider's terms.
