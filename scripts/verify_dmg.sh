#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/Codex-Toolbox.dmg" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"

DMG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
MOUNT_POINT="$(mktemp -d "${TMPDIR%/}/CodexToolbox-verify-mount.XXXXXX")"

cleanup() {
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rm -rf "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null

APP_PATH="$MOUNT_POINT/Codex Toolbox.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/Codex Toolbox"

test -d "$APP_PATH"
test -L "$MOUNT_POINT/Applications"
test -f "$MOUNT_POINT/DMG安装与升级说明.txt"
test -f "$MOUNT_POINT/.background/CodexToolbox-dmg-background.png"
test -f "$MOUNT_POINT/.DS_Store"
test "$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist")" = "io.github.zzzzzzjw.ShowCodexIQ"
test "$(plutil -extract LSUIElement raw "$APP_PATH/Contents/Info.plist")" = true
test "$(plutil -extract CodexToolboxReleaseVersion raw "$APP_PATH/Contents/Info.plist")" = "$RELEASE_VERSION"
test "$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")" = "$MARKETING_VERSION"
test "$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")" = "$BUILD_NUMBER"
test "$(plutil -extract SUEnableAutomaticChecks raw "$APP_PATH/Contents/Info.plist")" = true
test "$(plutil -extract SUAutomaticallyUpdate raw "$APP_PATH/Contents/Info.plist")" = true
test "$(plutil -extract SUScheduledCheckInterval raw "$APP_PATH/Contents/Info.plist")" = 86400
test "$(plutil -extract SUPublicEDKey raw "$APP_PATH/Contents/Info.plist")" = "$SPARKLE_PUBLIC_ED_KEY"
test -d "$APP_PATH/Contents/Frameworks/Sparkle.framework"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

APP_SIGNATURE="$(codesign -dvv "$APP_PATH" 2>&1)"
DMG_SIGNATURE="$(codesign -dvv "$DMG_PATH" 2>&1)"
if ! grep -q 'flags=.*runtime' <<<"$APP_SIGNATURE"; then
    echo "Expected Hardened Runtime to remain enabled" >&2
    exit 1
fi

ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
    echo "Expected Universal 2 executable, found: $ARCHITECTURES" >&2
    exit 1
fi

if otool -L "$EXECUTABLE" | grep -qE 'CodexToolboxCore(\.framework|\.dylib)'; then
    echo "CodexToolboxCore must be statically linked into the app executable" >&2
    exit 1
fi
if ! otool -L "$EXECUTABLE" | grep -q 'Sparkle.framework'; then
    echo "Sparkle.framework must be linked for in-app updates" >&2
    exit 1
fi

if [[ "${REQUIRE_DISTRIBUTION_SIGNATURE:-0}" == "1" ]]; then
    if ! grep -q 'Authority=Developer ID Application' <<<"$APP_SIGNATURE"; then
        echo "A Developer ID Application signature is required for the DMG app" >&2
        exit 1
    fi
    if ! grep -q 'Authority=Developer ID Application' <<<"$DMG_SIGNATURE"; then
        echo "A Developer ID Application signature is required for the DMG" >&2
        exit 1
    fi
fi

"$ROOT_DIR/scripts/verify_app_launch.sh" "$APP_PATH"

if [[ -f "$DMG_PATH.sha256" ]]; then
    (cd "$(dirname "$DMG_PATH")" && shasum -a 256 -c "$(basename "$DMG_PATH").sha256")
fi

echo "DMG verified: $(basename "$DMG_PATH")"
echo "Architectures: $ARCHITECTURES"
echo "Installer layout: background, Applications shortcut, and upgrade guide present"
