# Devpost submission — English

## Identity

**Project name**

Show Codex IQ

**Tagline**

Pick the right Codex model—without leaving your menu bar.

**Recommended track**

Developer Tools

**One-sentence pitch**

Show Codex IQ is a native macOS menu-bar app that turns live Codex benchmark data into glanceable quality, cost, latency, and personalized overall rankings.

## Project story

Paste the following Markdown into the Devpost **Project Story** field.

---

## Inspiration

Choosing a Codex model is not a one-dimensional decision. The model with the highest benchmark score may not be the fastest or the most economical, and the right trade-off can change as new results arrive.

Codex Radar already exposes useful benchmark snapshots, but repeatedly opening a browser, finding the relevant models, and comparing three metrics breaks the flow of development. I wanted the decision to be available where I already look all day: the macOS menu bar.

That led to one product question: **can model selection become a two-second glance instead of a browser task?**

## What it does

Show Codex IQ is a native macOS menu-bar application for comparing Codex model and reasoning-effort combinations.

- The menu bar shows the top two choices in a compact two-line layout.
- Users can rank by benchmark score, cost, latency, or a personalized overall score.
- The popover presents four coordinated leaderboards, expandable top-five results, data freshness, manual refresh, and local trend charts.
- A three-part weight control always keeps quality, cost, and latency at a valid 100% total, so changing priorities immediately recomputes the overall ranking without another network request.
- Model aliases, optional values, four rank styles, an icon toggle, and adaptive width keep scarce menu-bar space under control.
- The app loads the last successful snapshot before refreshing. A timeout or offline state never erases a useful ranking.
- It is a Universal 2 app for macOS 14+, with a downloadable DMG, no analytics SDK, no account credentials, and no third-party runtime dependency.

The result is a small decision surface for developers who care about capability **and** the operational cost of getting there.

## How we built it

The app is built with Swift 6, SwiftUI, AppKit, Swift Charts, Observation, URLSession, and ServiceManagement.

The data layer uses a tolerant `Codable` model for the public Codex Radar snapshot. `URLSessionRadarClient` sends cache validators and handles `200` and `304` responses. An actor-backed repository merges concurrent refreshes into one request, while `SnapshotStore` atomically persists the latest successful snapshot and local cost history. The UI receives explicit loading, refreshing, stale, and error states rather than treating the network as always available.

`RankingEngine` is a pure, independently tested component. Quality sorts high-to-low; cost and latency sort low-to-high. The overall leaderboard converts ranks to percentile scores, uses average ranks for ties, applies user-defined weights, and then uses deterministic tie-breakers.

SwiftUI drives the popover and settings, while `NSStatusItem` plus `NSHostingView` provides reliable compact two-line rendering in the menu bar. Newer macOS versions use native Liquid Glass where available, with a system-material fallback on macOS 14–15.

### Build Week scope

An early working prototype existed before the official submission window. I documented that six-commit baseline rather than claiming it as Build Week work. During the submission period, **Codex with GPT-5.6** helped meaningfully extend the project: it created the custom three-way weight interaction, trend visibility and adaptive popover behavior, compact adaptive menu-bar sizing, model aliases, public release documentation, and a safer packaging pipeline. Screenshot feedback and real launch failures drove the iterations. Codex diagnosed library validation, switched the app core to static linking, and added release verification that launches the packaged app in multiple configurations.

I made the product decisions—what problem mattered, which trade-offs users should control, how compact the menu-bar experience had to be, and which failures were unacceptable. Codex accelerated the loop from each decision to an implemented, tested release.

## Challenges we ran into

**A two-line menu-bar UI is not a normal app window.** A pure `MenuBarExtra` approach could not reliably deliver the compact width and rendering control the product required. We moved only the status item to AppKit and retained SwiftUI for the rest of the experience.

**Three weights must stay valid while two handles move.** There is no native three-segment range control for this interaction. We built a custom accessible control that clamps integer weights, always preserves a total of 100%, updates the ranking immediately, and offers a one-click 50/25/25 reset.

**Fresh data must not make the product fragile.** The app needed to handle missing metrics, unknown JSON fields, schema evolution, timeouts, conditional HTTP caching, concurrent refreshes, and offline launches without clearing the last useful answer.

**Shipping a real macOS build exposed issues that source tests could not.** One beta launched silently because an ad-hoc-signed app with Hardened Runtime hit library validation. We diagnosed the installed process, statically linked the app core, unified the DMG scripts, and added checks for signature validity, architecture, installer layout, SHA-256, and real launch behavior.

## Accomplishments that we're proud of

- Shipped a coherent native product, not a mock-up: an installable Universal 2 DMG, settings, offline behavior, trends, and a complete release path.
- Turned a three-metric decision into a menu-bar interaction that can take only a glance.
- Built a deterministic ranking engine with tie handling, missing-data rules, and live custom weighting.
- Preserved user trust under failure: stale data stays visible, refreshes are deduplicated, and errors are explicit but non-destructive.
- Kept the runtime small and inspectable: no third-party dependencies, telemetry, advertising, or credentials.
- Completed nine in-period commits across 87 changed files, with 2,576 insertions and 465 deletions, and produced five beta packages. The earlier six-commit prototype remains clearly separated as pre-period work.

## What we learned

The best abstraction boundary for a native menu-bar app is sometimes between frameworks: AppKit for precise status-item behavior, SwiftUI for the larger product surface.

We also learned that “live” data is only useful when the app is designed for stale and partial states. Caching, deterministic sorting, and explicit freshness indicators contribute as much to product trust as the visualization itself.

Most importantly, Codex was most effective when the collaboration had clear invariants. “Weights always total 100,” “a failed refresh never clears existing rankings,” and “the packaged DMG must actually launch” gave GPT-5.6 concrete outcomes to implement and verify. The human contribution was not removed; it moved toward product judgment, constraints, and accepting or rejecting each iteration.

## What's next for Show Codex IQ

Before wider distribution, the priorities are to complete data-source permission review and add Developer ID signing and notarization. Product work will focus on optional rank-change notifications, richer local history, exportable comparisons, English localization, and more accessibility coverage.

The longer-term goal is to make the ranking layer source-agnostic, so developers can compare models using benchmark feeds that they trust while keeping the same fast, native decision workflow.

---

## Custom submission fields

### Which category are you submitting to?

Developer Tools

### URL to your public or private code repo

https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox

### Project link and testing instructions

Public repository: https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox

Latest packaged beta: https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox/releases/tag/v0.1.0-beta.5

Testing path:

1. Use a Mac running macOS 14 or later. Both Apple Silicon and Intel are supported.
2. Download the `beta.5` Universal DMG and matching `.sha256` file.
3. Drag **Show Codex IQ** to **Applications** and launch it. The app appears only in the menu bar.
4. Because this beta is ad-hoc signed and not notarized, macOS may show an unidentified-developer warning. Follow the repository's documented **System Settings → Privacy & Security → Open Anyway** flow.
5. Click the two-line menu-bar item to inspect four rankings, expand a card, refresh data, and open Settings.
6. In Settings, change the menu-bar metric, drag the two handles in the overall-weight control, toggle trend charts, and add a menu-bar-only model alias.

No account, API key, sample database, or test credentials are required. Network access to `https://codexradar.com/current.json` is needed for a fresh snapshot; the last successful snapshot remains available offline after first use.

### `/feedback` Session ID

`019f60dc-d23e-7ad2-84a2-a739947f1277`

### Developer-tool installation, platform, and testing details

- **Supported platform:** macOS 14.0 or later.
- **Architectures:** Apple Silicon (`arm64`) and Intel (`x86_64`).
- **Install:** Download the Universal DMG, drag the app to `/Applications`, and launch it from Applications. The app is menu-bar-only and does not appear in the Dock.
- **Fastest test path:** Use the packaged `v0.1.0-beta.5` DMG; rebuilding is not required.
- **Build from source:** Install Xcode and XcodeGen, run `xcodegen generate`, then open `ShowCodexIQ.xcodeproj`. Core verification is also available with `swift run CoreVerification` and `swift test`.
- **Credentials:** None.
- **Data:** A fresh ranking needs access to the public Codex Radar snapshot; the app uses HTTP cache validators and a conservative refresh interval.
- **Signing note:** The current beta is ad-hoc signed, so first launch may require the documented Gatekeeper override. SHA-256 files are provided with every DMG.

## Suggested media

- **Thumbnail:** application icon on a dark navy-to-cyan radar background; add the short line “Model choice at a glance.”
- **Hero image:** the existing dashboard screenshot, cropped to preserve both the two-line menu bar and four ranking cards.
- **Video:** use the script in [`demo-video-script.md`](demo-video-script.md), keep it public on YouTube, and keep final duration below 3:00.
