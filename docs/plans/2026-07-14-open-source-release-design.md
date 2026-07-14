# Open-source release preparation design

The first downloadable release remains `0.1.0-beta.1` because the existing Universal 2 DMG, its filename, and its embedded full version already use that identifier. Re-labeling the unchanged artifact as `0.1.0` or `1.0.0` would create a visible mismatch. Earlier milestones are documented as internal `alpha` builds without tags or binary attachments.

The README follows the familiar open-source flow: identity and status badges, concise product value, features, installation and Gatekeeper guidance, requirements, data/privacy constraints, development and verification commands, version policy, contribution guidance, acknowledgements, and license. Its artwork points to the current radar/Codex/terminal icon source rather than the deleted asset-catalog icon.

Version values move into one Xcode configuration file containing the full SemVer value, Apple's numeric marketing version, and a monotonically increasing build number. Both DMG builders and the verifier read that configuration. Runtime metadata comes from the generated application bundle, so future releases do not require editing a Swift constant. `CHANGELOG.md` follows Keep a Changelog categories; the release guide defines the repeatable bump, test, build, tag, upload, and verification sequence.

The current private repository can receive the commit, tag, and pre-release safely. Making it public remains a separate action because the repository documentation requires the maintainer to confirm Codex Radar redistribution authorization before public binary distribution.
