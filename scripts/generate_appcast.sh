#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_APP="${XCODE_APP:-/Applications/Xcode-beta.app}"
SPARKLE_KEY_ACCOUNT="Digital-Twin-Technology-Laboratory.Codex-Toolbox"
SOURCE_PACKAGES_DIR="${SOURCE_PACKAGES_DIR:-$ROOT_DIR/.build/xcode-source-packages}"
source "$ROOT_DIR/scripts/version.sh"

DMG_PATH="${1:-$ROOT_DIR/dist/Codex-Toolbox-$RELEASE_VERSION-universal.dmg}"
APPCAST_PATH="$ROOT_DIR/dist/appcast.xml"
RELEASE_NOTES_PATH="$ROOT_DIR/docs/releases/v$RELEASE_VERSION.md"
WORK_DIR="$(mktemp -d "${TMPDIR%/}/CodexToolbox-appcast.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

test -f "$DMG_PATH"
test -f "$RELEASE_NOTES_PATH"

if [[ ! -x "$XCODE_APP/Contents/Developer/usr/bin/xcodebuild" ]]; then
    echo "Xcode not found at: $XCODE_APP" >&2
    exit 1
fi

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
export TOOLCHAINS="${TOOLCHAINS:-com.apple.dt.toolchain.XcodeDefault}"

mkdir -p "$SOURCE_PACKAGES_DIR" "$ROOT_DIR/dist"
if command -v xcodegen >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && xcodegen generate)
fi

xcodebuild -resolvePackageDependencies \
    -project "$ROOT_DIR/CodexToolbox.xcodeproj" \
    -scheme CodexToolbox \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR"

GENERATE_APPCAST="$SOURCE_PACKAGES_DIR/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$GENERATE_APPCAST" ]]; then
    echo "Sparkle generate_appcast tool was not resolved at: $GENERATE_APPCAST" >&2
    exit 1
fi

DMG_NAME="$(basename "$DMG_PATH")"
ditto --noextattr --noqtn --noacl "$DMG_PATH" "$WORK_DIR/$DMG_NAME"
ditto --noextattr --noqtn --noacl \
    "$RELEASE_NOTES_PATH" \
    "$WORK_DIR/${DMG_NAME%.dmg}.txt"

"$GENERATE_APPCAST" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --download-url-prefix "https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox/releases/download/v$RELEASE_VERSION/" \
    --link "https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox/releases/tag/v$RELEASE_VERSION" \
    --embed-release-notes \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    -o "$APPCAST_PATH" \
    "$WORK_DIR"

xmllint --noout "$APPCAST_PATH"
grep -q "sparkle:edSignature=" "$APPCAST_PATH"
grep -q "releases/download/v$RELEASE_VERSION/$DMG_NAME" "$APPCAST_PATH"

echo "Sparkle appcast created: $APPCAST_PATH"
