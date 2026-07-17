# OpenAI Build Week submission checklist

Official submission deadline: **July 21, 2026 at 5:00 PM Pacific Time**, which is **July 22, 2026 at 08:00 China Standard Time**. Aim to finish at least 12 hours earlier.

## 0. Resolve the two compliance gates first

- [ ] **Eligibility:** Confirm the entrant's legal country or territory of residence against the official rules. The current included-country list does **not** list mainland China. A Shanghai time zone or physical location does not by itself establish legal residence, so use the entrant's true legal residence. If it is mainland China, obtain written clarification from `support@devpost.com` before investing in the final submission.
- [ ] **Third-party data authorization:** Obtain written permission from Codex Radar for this hackathon submission and binary distribution, or change the judge build to use data that the entrant is authorized to distribute. The official rules require authorization for third-party APIs/data, while `docs/data-source.md` records that broader API and secondary-development use may require permission.
- [ ] Save written permissions or clarifications with the project records.

Do not hide either issue in the submission. If permission is pending, do not describe the live feed as cleared for unrestricted public distribution.

## 1. Devpost identity

- [ ] Rename the online project from `Codex Toolbox` to `Show Codex IQ`.
- [ ] Use the tagline: `Pick the right Codex model—without leaving your menu bar.`
- [ ] Select exactly one category: `Developer Tools`.
- [ ] Select the entrant's legally accurate eligible country or territory.
- [ ] Confirm all real team members are added and have accepted invitations; do not add nominal members only to alter eligibility.

## 2. Project story

- [ ] Paste `devpost-submission-en.md` into the Project Story field.
- [ ] Read it once in your own voice and edit any sentence you would not naturally say.
- [ ] Keep the distinction clear: the app was **built with** Codex/GPT‑5.6; it does not call GPT‑5.6 at runtime.
- [ ] Keep the independent-project and data-source attribution statement.
- [ ] Confirm every feature mentioned is present in `v0.1.0-beta.5` or the final release used in the video.

## 3. Required custom fields

- [ ] **Repository:** `https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox`
- [ ] Confirm the repository is public and still uses the MIT license.
- [ ] **Testing link:** use the final GitHub Release URL.
- [ ] Paste the installation and testing text from the English submission file.
- [ ] **Primary in-period `/feedback` Session ID:** `019f60dc-d23e-7ad2-84a2-a739947f1277`
- [ ] Paste the Developer Tools platform/install/test response.
- [ ] Add no credentials because none are required.

## 4. README and repository

- [ ] README links to `docs/hackathon/judges-guide.md`.
- [ ] README explicitly explains how Codex and GPT‑5.6 were used.
- [ ] README distinguishes human product decisions from Codex acceleration.
- [ ] README includes install and source-build instructions.
- [ ] README links to the exact final release used by judges.
- [ ] `swift test` and `swift run CoreVerification` pass from a clean checkout.
- [ ] `scripts/verify_dmg.sh <final-dmg>` passes.
- [ ] The final release includes both the DMG and `.sha256`.
- [ ] The release notes mention supported macOS versions and the ad-hoc signing limitation.
- [ ] The Git commit range covering Build Week work remains visible and dated.
- [ ] The six pre-period commits are explicitly separated from the nine in-period commits; do not claim the project was created from zero during the submission window.

## 5. Demo video

- [ ] Follow `demo-video-script.md` and keep the final cut below 3:00.
- [ ] Show the real app working; do not submit a slide-only video.
- [ ] Voice-over explicitly explains what was built and says how **Codex** and **GPT‑5.6** were used.
- [ ] Show the compact menu bar, four rankings, custom weights, settings, and freshness/offline behavior.
- [ ] Include the repository URL on screen.
- [ ] Remove copyrighted music unless permission is documented.
- [ ] Add accurate English captions.
- [ ] Upload to YouTube with visibility set to **Public**.
- [ ] Test the final YouTube URL in a signed-out/private browser window.
- [ ] Paste the URL into Devpost and preview it.

## 6. Visual assets

- [ ] Use the real application icon, not an unrelated AI-generated logo.
- [ ] Prepare a clean project thumbnail with the app icon and the line `Model choice at a glance`.
- [ ] Use `docs/assets/screenshots/dashboard.png` as the main product image.
- [ ] If possible, capture one additional English-language or bilingual screenshot for international judges.
- [ ] Check all images at Devpost preview size; menu-bar text must remain legible.
- [ ] Keep OpenAI and Codex Radar marks contextual; do not imply official endorsement.

## 7. Final submission QA

- [ ] Preview the public project page from top to bottom.
- [ ] Check every link: repository, release, video, data source, and documentation.
- [ ] Confirm the project name is consistent across Devpost, GitHub, DMG, and video.
- [ ] Confirm the video and text describe the same final build.
- [ ] Confirm no secret, email address, private notification, or private session content is visible.
- [ ] Confirm the project is no longer marked `submission_draft` after submission.
- [ ] Save screenshots of the final confirmation page and submission time.

## Current readiness snapshot — July 16, 2026

- **Complete:** working native app, public repository, MIT license, installation documentation, release DMG, checksum, Universal 2 package, primary Session ID, commit history, project story draft, judge guide, and demo script.
- **Still required:** eligibility confirmation, third-party data permission or an authorized-data fallback, public YouTube demo, thumbnail/additional media, final Devpost field entry, and final submit action.
