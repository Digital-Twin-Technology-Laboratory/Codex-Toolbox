#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/Show-Codex-IQ.dmg" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"

DMG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
MOUNT_POINT="${TMPDIR%/}/ShowCodexIQ-verify-mount"
SMOKE_DIR="${TMPDIR%/}/ShowCodexIQ-launch-smoke"
SMOKE_PID=""

cleanup() {
    if [[ -n "$SMOKE_PID" ]] && kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
        kill "$SMOKE_PID" >/dev/null 2>&1 || true
        wait "$SMOKE_PID" >/dev/null 2>&1 || true
    fi
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rm -rf "$MOUNT_POINT" "$SMOKE_DIR" >/dev/null 2>&1 || true
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
test -f "$MOUNT_POINT/.background/ShowCodexIQ-dmg-background.png"
test -f "$MOUNT_POINT/.DS_Store"
test "$(plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist")" = true
test "$(plutil -extract ShowCodexIQReleaseVersion raw "$APP_PATH/Contents/Info.plist")" = "$RELEASE_VERSION"
test "$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")" = "$MARKETING_VERSION"
test "$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")" = "$BUILD_NUMBER"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

CODESIGN_DETAILS="$(codesign -dvv "$APP_PATH" 2>&1)"
if ! grep -q 'flags=.*runtime' <<<"$CODESIGN_DETAILS"; then
    echo "Expected Hardened Runtime to remain enabled" >&2
    exit 1
fi

ARCHS="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "Expected Universal 2 executable, found: $ARCHS" >&2
    exit 1
fi

LINKED_LIBRARIES="$(otool -L "$EXECUTABLE")"
if grep -qE 'ShowCodexIQCore(\.framework|\.dylib)' <<<"$LINKED_LIBRARIES"; then
    echo "ShowCodexIQCore must be statically linked into the app executable" >&2
    exit 1
fi

rm -rf "$SMOKE_DIR"
mkdir -p "$SMOKE_DIR/home"
CFFIXED_USER_HOME="$SMOKE_DIR/home" \
    "$EXECUTABLE" \
    >"$SMOKE_DIR/stdout.log" \
    2>"$SMOKE_DIR/stderr.log" &
SMOKE_PID=$!
sleep 3

if ! kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
    wait "$SMOKE_PID" >/dev/null 2>&1 || true
    echo "App exited during the launch smoke test" >&2
    if [[ -s "$SMOKE_DIR/stderr.log" ]]; then
        sed -n '1,120p' "$SMOKE_DIR/stderr.log" >&2
    fi
    exit 1
fi

kill "$SMOKE_PID" >/dev/null 2>&1 || true
wait "$SMOKE_PID" >/dev/null 2>&1 || true
SMOKE_PID=""

if [[ -f "$DMG_PATH.sha256" ]]; then
    (cd "$(dirname "$DMG_PATH")" && shasum -a 256 -c "$(basename "$DMG_PATH").sha256")
fi

echo "DMG verified: $(basename "$DMG_PATH")"
echo "Architectures: $ARCHS"
echo "Installer layout: background and Finder layout present"
echo "Launch smoke test: passed"
