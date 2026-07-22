#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_APP="${XCODE_APP:-/Applications/Xcode-beta.app}"
source "$ROOT_DIR/scripts/version.sh"

BUILD_DIR="$(mktemp -d "${TMPDIR%/}/CodexToolbox-dmg-archive.XXXXXX")"
ARCHIVE_PATH="$BUILD_DIR/CodexToolbox.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Codex Toolbox.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/Codex Toolbox"
OUTPUT_DMG="$ROOT_DIR/dist/Codex-Toolbox-$RELEASE_VERSION-universal.dmg"

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

if [[ ! -x "$XCODE_APP/Contents/Developer/usr/bin/xcodebuild" ]]; then
    echo "Xcode not found at: $XCODE_APP" >&2
    exit 1
fi

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
export TOOLCHAINS="${TOOLCHAINS:-com.apple.dt.toolchain.XcodeDefault}"

mkdir -p "$ROOT_DIR/dist"
if command -v xcodegen >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && xcodegen generate)
fi

xcodebuild archive \
    -project "$ROOT_DIR/CodexToolbox.xcodeproj" \
    -scheme CodexToolbox \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    SKIP_INSTALL=NO

test -d "$APP_PATH"
ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
    echo "Expected Universal 2 executable, found: $ARCHITECTURES" >&2
    exit 1
fi

xattr -cr "$APP_PATH"
if [[ -n "${APP_SIGN_IDENTITY:-}" ]]; then
    "$ROOT_DIR/scripts/sign_app.sh" "$APP_PATH" "$APP_SIGN_IDENTITY"
else
    "$ROOT_DIR/scripts/sign_app.sh" "$APP_PATH" -
    echo "Applied an ad-hoc development signature; Developer ID Application signing is still required." >&2
fi

"$ROOT_DIR/scripts/package_dmg.sh" \
    "$APP_PATH" \
    "$OUTPUT_DMG" \
    "Codex Toolbox $RELEASE_VERSION"

if [[ -n "${APP_SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$APP_SIGN_IDENTITY" "$OUTPUT_DMG"
else
    codesign --force --sign - --timestamp=none "$OUTPUT_DMG"
fi

(
    cd "$(dirname "$OUTPUT_DMG")"
    shasum -a 256 "$(basename "$OUTPUT_DMG")" > "$(basename "$OUTPUT_DMG").sha256"
)

"$ROOT_DIR/scripts/verify_dmg.sh" "$OUTPUT_DMG"
echo "Architectures: $ARCHITECTURES"
