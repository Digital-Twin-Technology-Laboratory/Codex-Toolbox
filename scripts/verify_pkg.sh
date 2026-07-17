#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/Codex-Toolbox.pkg" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"

PKG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
BUILD_DIR="$(mktemp -d "${TMPDIR%/}/CodexToolbox-verify.XXXXXX")"
EXPANDED="$BUILD_DIR/expanded"

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

test -f "$PKG_PATH"
/usr/sbin/pkgutil --expand-full "$PKG_PATH" "$EXPANDED"

APP_PATH="$(find "$EXPANDED" -type d -name 'Codex Toolbox.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
    echo "Expanded package did not contain Codex Toolbox.app" >&2
    exit 1
fi

PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/Codex Toolbox"
test "$(plutil -extract CFBundleIdentifier raw "$PLIST")" = "io.github.zzzzzzjw.ShowCodexIQ"
test "$(plutil -extract CodexToolboxReleaseVersion raw "$PLIST")" = "$RELEASE_VERSION"
test "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" = "$MARKETING_VERSION"
test "$(plutil -extract CFBundleVersion raw "$PLIST")" = "$BUILD_NUMBER"
test "$(plutil -extract LSUIElement raw "$PLIST")" = true

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
CODESIGN_DETAILS="$(codesign -dvv "$APP_PATH" 2>&1)"
if ! grep -q 'flags=.*runtime' <<<"$CODESIGN_DETAILS"; then
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

test -x "$EXPANDED"/*/Scripts/preinstall
test -x "$EXPANDED"/*/Scripts/postinstall

SIGNATURE_OUTPUT="$(pkgutil --check-signature "$PKG_PATH" 2>&1 || true)"
if [[ "${REQUIRE_DISTRIBUTION_SIGNATURE:-0}" == "1" ]]; then
    if ! grep -q 'Developer ID Installer' <<<"$SIGNATURE_OUTPUT"; then
        echo "A Developer ID Installer signature is required" >&2
        echo "$SIGNATURE_OUTPUT" >&2
        exit 1
    fi
    if ! grep -q 'Developer ID Application' <<<"$CODESIGN_DETAILS"; then
        echo "A Developer ID Application signature is required" >&2
        exit 1
    fi
fi

if [[ -f "$PKG_PATH.sha256" ]]; then
    (cd "$(dirname "$PKG_PATH")" && shasum -a 256 -c "$(basename "$PKG_PATH").sha256")
fi

echo "PKG verified: $(basename "$PKG_PATH")"
echo "Architectures: $ARCHITECTURES"
if grep -q 'Developer ID Installer' <<<"$SIGNATURE_OUTPUT"; then
    echo "Installer signature: Developer ID Installer"
else
    echo "Installer signature: unsigned development artifact"
fi
