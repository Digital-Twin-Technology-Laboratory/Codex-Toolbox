#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/Show-Codex-IQ.dmg" >&2
    exit 2
fi

DMG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
MOUNT_POINT="${TMPDIR%/}/ShowCodexIQ-verify-mount"

cleanup() {
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rm -rf "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf "$MOUNT_POINT"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null

APP_PATH="$MOUNT_POINT/Show Codex IQ.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/Show Codex IQ"

test -d "$APP_PATH"
test -L "$MOUNT_POINT/Applications"
test -f "$MOUNT_POINT/首次打开说明.txt"
test "$(plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist")" = true
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ARCHS="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "Expected Universal 2 executable, found: $ARCHS" >&2
    exit 1
fi

if [[ -f "$DMG_PATH.sha256" ]]; then
    (cd "$(dirname "$DMG_PATH")" && shasum -a 256 -c "$(basename "$DMG_PATH").sha256")
fi

echo "DMG verified: $(basename "$DMG_PATH")"
echo "Architectures: $ARCHS"
