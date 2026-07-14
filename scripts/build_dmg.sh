#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_APP="${XCODE_APP:-/Applications/Xcode-beta.app}"
source "$ROOT_DIR/scripts/version.sh"
VERSION="$RELEASE_VERSION"
BUILD_DIR="${TMPDIR%/}/ShowCodexIQ-xcode-dmg"
ARCHIVE_PATH="$BUILD_DIR/ShowCodexIQ.xcarchive"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$BUILD_DIR/dmg-root"
DMG_NAME="Show-Codex-IQ-$VERSION-universal.dmg"

if [[ ! -x "$XCODE_APP/Contents/Developer/usr/bin/xcodebuild" ]]; then
    echo "Xcode not found at: $XCODE_APP" >&2
    echo "Install Xcode 27 beta there, or set XCODE_APP=/path/to/Xcode.app." >&2
    exit 1
fi

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

if command -v xcodegen >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && xcodegen generate)
fi

xcodebuild archive \
    -project "$ROOT_DIR/ShowCodexIQ.xcodeproj" \
    -scheme ShowCodexIQ \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    SKIP_INSTALL=NO

APP_PATH="$ARCHIVE_PATH/Products/Applications/Show Codex IQ.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/Show Codex IQ"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Archive did not contain Show Codex IQ.app" >&2
    exit 1
fi

ARCHS="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "Expected Universal 2 executable, found: $ARCHS" >&2
    exit 1
fi

xattr -cr "$APP_PATH"
codesign --force --deep --options runtime --sign - --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto --noextattr --noqtn --noacl "$APP_PATH" "$STAGE_DIR/Show Codex IQ.app"
ln -s /Applications "$STAGE_DIR/Applications"
ditto --noextattr --noqtn --noacl "$ROOT_DIR/docs/distribution/首次打开说明.txt" "$STAGE_DIR/首次打开说明.txt"
codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/Show Codex IQ.app"

rm -f "$DIST_DIR/$DMG_NAME" "$DIST_DIR/$DMG_NAME.sha256"
hdiutil create \
    -volname "Show Codex IQ $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -format UDZO \
    -ov \
    "$DIST_DIR/$DMG_NAME"

(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "Created: $DIST_DIR/$DMG_NAME"
echo "Architectures: $ARCHS"
cat "$DIST_DIR/$DMG_NAME.sha256"
