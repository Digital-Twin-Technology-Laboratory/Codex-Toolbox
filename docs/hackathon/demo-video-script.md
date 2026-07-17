# Demo video script — target 2:45

The Build Week video must be a **public YouTube video under three minutes**. It must show the working product and include spoken audio explaining how both Codex and GPT‑5.6 were used.

## Recording setup

- Record at 1920 × 1080 or higher, 30 fps.
- Hide personal notifications and unrelated menu-bar items.
- Use a clean desktop wallpaper with enough contrast behind the menu bar.
- Set the app to a snapshot with at least three complete model entries.
- Keep the cursor movements deliberate; pause briefly after each click.
- Record the voice-over separately if live narration makes the interaction rushed.
- Add English captions and keep the final cut between 2:35 and 2:50.

## Script

### 0:00–0:18 — Hook

**Shot:** Start on the macOS desktop. Briefly highlight the two-line Show Codex IQ item in the menu bar.

**Voice-over:**

> Choosing a Codex model is a three-way decision: capability, cost, and latency. The best answer changes as new benchmark results arrive, but reopening a website every time breaks my development flow. Show Codex IQ turns that lookup into a two-second glance at the macOS menu bar.

**On-screen caption:** `Model choice at a glance`

### 0:18–0:43 — The compact answer

**Shot:** Zoom slightly into the menu bar. Open Settings, switch the menu-bar metric from IQ to Overall, then return.

**Voice-over:**

> The menu bar shows the top two model and reasoning-effort combinations in two compact rows. I can rank by benchmark score, lowest cost, lowest latency, or my own overall score. The width adapts to the content, and I can hide values, change rank styles, remove the icon, or assign short aliases when space is tight.

### 0:43–1:18 — Full dashboard

**Shot:** Click the status item. Show freshness status and the four cards. Expand one card to Top 5, then click refresh.

**Voice-over:**

> One click opens four coordinated leaderboards: highest IQ, lowest cost, lowest latency, and best overall trade-off. Each card starts with the top three and expands to five without turning the popover into a dense table. The header shows when the benchmark was tested and fetched. Refresh is explicit, and trend charts can be shown when they help or hidden when I want a smaller panel.

### 1:18–1:48 — Personal ranking

**Shot:** Open Settings and drag both handles of the three-part weight control. Show the labels changing and then return to the overall card.

**Voice-over:**

> Different tasks need different trade-offs, so the overall ranking is not hard-coded. This custom three-part control allocates one hundred percent across quality, cost, and latency. Moving either handle keeps the total valid and recomputes the ranking immediately—no new network request and no invalid intermediate state.

**On-screen caption:** `Quality + Cost + Latency = 100%`

### 1:48–2:12 — Reliability and privacy

**Shot:** Show the data-status area, then a quick graphic or terminal overlay listing `ETag / 304`, `single-flight`, and `offline snapshot`.

**Voice-over:**

> Under the interface, an actor-backed repository deduplicates concurrent refreshes, HTTP validators avoid unnecessary downloads, and the last successful snapshot is stored atomically. If the network fails, the app marks the data stale but never erases the last useful answer. There are no analytics SDKs, ads, accounts, or credentials.

### 2:12–2:38 — How Codex and GPT‑5.6 were used

**Shot:** Show a fast montage: the primary Codex task title or session, the architecture plan, a Swift source file, tests, Git history, and the DMG verification output.

**Voice-over:**

> An early prototype existed before the submission window, and I documented that baseline. During Build Week, I used Codex with GPT‑5.6 to substantially extend it: a custom three-way weight control, adaptive menu-bar and popover layouts, model aliases, public release documentation, and a safer packaging pipeline. I supplied product constraints, screenshots, and real failures; Codex diagnosed library validation, moved the core to static linking, and added release checks that launch the packaged app. I owned the decisions and acceptance criteria; GPT‑5.6 accelerated each path from decision to verified release.

**On-screen caption:** `In-period Session: 019f60dc-d23e-7ad2-84a2-a739947f1277`

### 2:38–2:48 — Close

**Shot:** Return to the complete dashboard, then end on the icon, project name, repository, and “Developer Tools” label.

**Voice-over:**

> Show Codex IQ makes model selection visible, personal, and fast—without leaving the menu bar. The code and latest packaged DMG are available on GitHub.

## Final video QA

- Duration is strictly below 3:00.
- Product is visibly working; do not rely only on slides.
- Audio explicitly says both “Codex” and “GPT‑5.6.”
- Repository URL is readable for at least three seconds.
- No private session content, email address, token, or notification is visible.
- Captions match the final audio.
- YouTube visibility is **Public**, not Unlisted or Private.
