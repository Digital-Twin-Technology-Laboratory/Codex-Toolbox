#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"

PKG_PATH="$ROOT_DIR/dist/Codex-Toolbox-$RELEASE_VERSION-universal.pkg"
PKG_CHECKSUM_PATH="$PKG_PATH.sha256"
DMG_PATH="$ROOT_DIR/dist/Codex-Toolbox-$RELEASE_VERSION-universal.dmg"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"
APPCAST_PATH="$ROOT_DIR/dist/appcast.xml"

verify_remote_manifest() {
    local relative_path="$1"
    local local_path="$ROOT_DIR/$relative_path"
    local remote_url="https://raw.githubusercontent.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox/main/$relative_path"
    local downloaded
    downloaded="$(mktemp "${TMPDIR%/}/CodexToolbox-remote-manifest.XXXXXX")"

    for attempt in 1 2 3 4; do
        if curl --fail --silent --show-error --location \
            --connect-timeout 10 --max-time 30 \
            "$remote_url" -o "$downloaded" \
            && cmp -s "$local_path" "$downloaded"; then
            rm -f "$downloaded"
            return 0
        fi
        sleep 3
    done

    rm -f "$downloaded"
    echo "Remote manifest is missing or differs from the release commit: $remote_url" >&2
    return 1
}

: "${ALLOW_GITHUB_RELEASE:?Set ALLOW_GITHUB_RELEASE=YES only after signing and notarization are complete}"
if [[ "$ALLOW_GITHUB_RELEASE" != "YES" ]]; then
    echo "ALLOW_GITHUB_RELEASE must equal YES" >&2
    exit 1
fi

REQUIRE_DISTRIBUTION_SIGNATURE=1 "$ROOT_DIR/scripts/verify_pkg.sh" "$PKG_PATH"
REQUIRE_DISTRIBUTION_SIGNATURE=1 "$ROOT_DIR/scripts/verify_dmg.sh" "$DMG_PATH"
xcrun stapler validate "$PKG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type install --verbose=4 "$PKG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
"$ROOT_DIR/scripts/generate_appcast.sh" "$DMG_PATH"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    echo "The repository must be clean before creating the release tag." >&2
    exit 1
fi

CURRENT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "The release must be created from the main branch, found: $CURRENT_BRANCH" >&2
    exit 1
fi

git -C "$ROOT_DIR" fetch origin main
if ! git -C "$ROOT_DIR" merge-base --is-ancestor origin/main HEAD; then
    echo "Local main has diverged from origin/main; reconcile it before releasing." >&2
    exit 1
fi

git -C "$ROOT_DIR" push origin main
verify_remote_manifest "Sources/CodexToolbox/Resources/codex-rate-card-v1.json"
verify_remote_manifest "Sources/CodexToolbox/Resources/api-price-card-v1.json"
git -C "$ROOT_DIR" tag -a "v$RELEASE_VERSION" -m "Codex Toolbox v$RELEASE_VERSION"
git -C "$ROOT_DIR" push origin "v$RELEASE_VERSION"
gh release create "v$RELEASE_VERSION" \
    "$PKG_PATH" \
    "$PKG_CHECKSUM_PATH" \
    "$DMG_PATH" \
    "$DMG_CHECKSUM_PATH" \
    "$APPCAST_PATH" \
    --repo Digital-Twin-Technology-Laboratory/Codex-Toolbox \
    --title "Codex Toolbox v$RELEASE_VERSION" \
    --notes-file "$ROOT_DIR/docs/releases/v$RELEASE_VERSION.md" \
    --latest
