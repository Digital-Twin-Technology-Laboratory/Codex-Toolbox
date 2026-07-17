# Six-slide pitch deck outline

This deck is optional for Devpost, but useful as a recording storyboard, live-demo backup, and source for a project thumbnail or social post. Keep it visual: one message per slide, minimal prose, and the real app screenshot as the central artifact.

## Visual direction

- **Tone:** native macOS precision, not generic AI gradients.
- **Palette:** midnight navy, radar cyan, cost green, latency amber, overall magenta.
- **Type:** SF Pro or a clean neo-grotesk; use monospaced numerals for metrics.
- **Motif:** concentric radar rings and a compact two-row status item.
- **Primary asset:** `docs/assets/screenshots/dashboard.png`.
- **Logo asset:** `design/icon-concepts/codex-radar-terminal-b-preview.png`.

## Slide 1 — The two-second model decision

**Headline:** Pick the right Codex model—without leaving your menu bar.

**Visual:** Full-height product screenshot with a callout around the two-line menu-bar item.

**Footer:** Show Codex IQ · OpenAI Build Week · Developer Tools

**Speaker point:** Model selection is a recurring quality/cost/latency decision; the product compresses it into a glance.

## Slide 2 — The problem is three-dimensional

**Headline:** Highest capability ≠ lowest cost ≠ fastest result

**Visual:** A simple quality / cost / latency triangle with three different “winner” chips.

**Proof points:**

- Results change as benchmarks update.
- Browser lookup interrupts the coding loop.
- The right trade-off is personal and task-dependent.

**Speaker point:** This is not another benchmark dashboard; it is the decision surface that sits between benchmark data and daily development.

## Slide 3 — One glance, four rankings, your weights

**Headline:** From live snapshot to a personal answer

**Visual flow:** `Codex Radar snapshot → deterministic ranking engine → menu bar + four cards`.

**Callouts:**

- Top two always visible.
- IQ, cost, latency, or overall.
- Three-way weights always total 100%.
- Offline snapshot preserves the last useful answer.

## Slide 4 — Native product, engineered for failure

**Headline:** Small surface. Serious engineering.

**Visual:** Four compact architecture blocks:

1. `URLSession + ETag / 304`
2. `actor single-flight repository`
3. `pure deterministic RankingEngine`
4. `SwiftUI + AppKit + Swift Charts`

**Proof bar:** macOS 14+ · Universal 2 · no third-party runtime dependencies · no telemetry

**Speaker point:** The hardest work is invisible: partial JSON, concurrent refreshes, stale state, precise menu-bar rendering, and a DMG that actually launches.

## Slide 5 — Human judgment × Codex velocity

**Headline:** Product constraints became verified releases

**Visual:** A two-lane timeline.

- **Human lane:** problem choice → compactness → controllable trade-offs → failure criteria → iteration acceptance
- **Codex + GPT‑5.6 lane:** architecture → implementation → tests → screenshot-driven fixes → launch diagnosis → packaging verification

**Evidence:**

- Primary in-period Session ID: `019f60dc-d23e-7ad2-84a2-a739947f1277`
- Six-commit pre-period baseline documented separately
- Nine in-period commits across 87 files
- Five beta packages during the submission window

**Speaker point:** Codex did not invent a vague demo; it helped execute against explicit, testable product invariants.

## Slide 6 — Impact and next step

**Headline:** Make model choice ambient, trusted, and personal

**Near-term:**

- Data-source permission review
- Developer ID signing and notarization
- Rank-change notifications
- Richer local history and export
- English localization and accessibility coverage

**Closing line:** The best model is not a brand name. It is the best trade-off for the task in front of you.

**CTA:** GitHub repository + release QR code
