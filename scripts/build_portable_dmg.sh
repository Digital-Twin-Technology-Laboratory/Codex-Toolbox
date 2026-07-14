#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
VERSION="$RELEASE_VERSION"
BUILD_DIR="${TMPDIR%/}/ShowCodexIQ-portable-dmg"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$BUILD_DIR/Show Codex IQ.app"
STAGE_DIR="$BUILD_DIR/dmg-root"
MOUNT_DIR="$BUILD_DIR/dmg-mount"
RW_DMG="$BUILD_DIR/ShowCodexIQ-installer-rw.dmg"
DMG_NAME="Show-Codex-IQ-$VERSION-universal-portable.dmg"
VOL_NAME="Show Codex IQ Installer"
BUILD_VOL_NAME="$VOL_NAME Build $$"
BACKGROUND_SOURCE="$ROOT_DIR/design/dmg/ShowCodexIQ-dmg-background.png"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
DEVICE=""

cleanup() {
    if [[ -n "$DEVICE" ]]; then
        diskutil eject "$DEVICE" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

if [[ ! -f "$BACKGROUND_SOURCE" ]]; then
    echo "Missing DMG background: $BACKGROUND_SOURCE" >&2
    exit 1
fi

"$ROOT_DIR/scripts/generate_app_icon.swift"

core_sources=()
while IFS= read -r source; do
    core_sources+=("$source")
done < <(find "$ROOT_DIR/Sources/ShowCodexIQCore" -name '*.swift' -type f | sort)

app_sources=()
while IFS= read -r source; do
    app_sources+=("$source")
done < <(find "$ROOT_DIR/Sources/ShowCodexIQ" -name '*.swift' -type f | sort)

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

for arch in arm64 x86_64; do
    ARCH_DIR="$BUILD_DIR/$arch"
    mkdir -p "$ARCH_DIR"

    "$SWIFTC" \
        -parse-as-library \
        -O \
        -swift-version 6 \
        -target "$arch-apple-macosx14.0" \
        -sdk "$SDK_PATH" \
        -module-name ShowCodexIQCore \
        -emit-module \
        -emit-module-path "$ARCH_DIR/ShowCodexIQCore.swiftmodule" \
        -emit-library \
        -static \
        "${core_sources[@]}" \
        -o "$ARCH_DIR/libShowCodexIQCore.a"

    "$SWIFTC" \
        -parse-as-library \
        -O \
        -swift-version 6 \
        -target "$arch-apple-macosx14.0" \
        -sdk "$SDK_PATH" \
        -I "$ARCH_DIR" \
        "${app_sources[@]}" \
        -L "$ARCH_DIR" \
        -lShowCodexIQCore \
        -o "$ARCH_DIR/Show Codex IQ"
done

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
lipo -create \
    "$BUILD_DIR/arm64/Show Codex IQ" \
    "$BUILD_DIR/x86_64/Show Codex IQ" \
    -output "$APP_PATH/Contents/MacOS/Show Codex IQ"

cp "$ROOT_DIR/Sources/ShowCodexIQ/Config/Info.plist" "$APP_PATH/Contents/Info.plist"
PLIST="$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion zh_CN" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Show Codex IQ" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.zzzzzzjw.ShowCodexIQ" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Show Codex IQ" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Show Codex IQ" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :ShowCodexIQReleaseVersion $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST"

ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$ROOT_DIR"/design/icon-composer/ShowCodexIQLegacy.iconset/icon_*.png "$ICONSET/"
iconutil --convert icns --output "$APP_PATH/Contents/Resources/AppIcon.icns" "$ICONSET"

chmod 755 "$APP_PATH/Contents/MacOS/Show Codex IQ"
xattr -cr "$APP_PATH"
codesign --force --deep --options runtime --sign - --timestamp=none "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/Show Codex IQ")"
if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "Expected Universal 2 executable, found: $ARCHS" >&2
    exit 1
fi

mkdir -p "$STAGE_DIR"
ditto --noextattr --noqtn --noacl "$APP_PATH" "$STAGE_DIR/Show Codex IQ.app"
ln -s /Applications "$STAGE_DIR/Applications"
ditto --noextattr --noqtn --noacl "$ROOT_DIR/docs/distribution/首次打开说明.txt" "$STAGE_DIR/首次打开说明.txt"
mkdir -p "$STAGE_DIR/.background"
ditto --noextattr --noqtn --noacl "$BACKGROUND_SOURCE" "$STAGE_DIR/.background/ShowCodexIQ-dmg-background.png"
codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/Show Codex IQ.app"

rm -f "$DIST_DIR/$DMG_NAME" "$DIST_DIR/$DMG_NAME.sha256" "$RW_DMG"
diskutil image create blank \
    --format RAW \
    --size 200m \
    --volumeName "$BUILD_VOL_NAME" \
    --fs APFS \
    "$RW_DMG"

ATTACH_OUTPUT="$(diskutil image attach "$RW_DMG")"
DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/GUID_partition_scheme/ {print $1; exit}')"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F '\t' '/\/Volumes\// {print $NF; exit}')"
MOUNT_DIR="${MOUNT_DIR#${MOUNT_DIR%%[![:space:]]*}}"

if [[ -z "$DEVICE" || -z "$MOUNT_DIR" ]]; then
    echo "Unable to determine mounted DMG device or volume" >&2
    exit 1
fi

ditto --noextattr --noqtn --noacl "$STAGE_DIR" "$MOUNT_DIR"
sleep 1

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$BUILD_VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set sidebar width of container window to 0
        set the bounds of container window to {120, 120, 780, 540}

        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 104
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:ShowCodexIQ-dmg-background.png"

        set position of item "Show Codex IQ.app" of container window to {165, 218}
        set position of item "Applications" of container window to {495, 218}

        set selection of application "Finder" to {}
        update without registering applications
        delay 2
        close container window
    end tell
end tell
APPLESCRIPT

if [[ ! -f "$MOUNT_DIR/.DS_Store" ]]; then
    echo "Finder did not persist the DMG window layout" >&2
    exit 1
fi

sync
diskutil rename "$MOUNT_DIR" "$VOL_NAME" >/dev/null
diskutil eject "$DEVICE"
DEVICE=""

diskutil image create from \
    --format UDZO \
    "$RW_DMG" \
    "$DIST_DIR/$DMG_NAME"

(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "Created portable verification build: $DIST_DIR/$DMG_NAME"
echo "Architectures: $ARCHS"
cat "$DIST_DIR/$DMG_NAME.sha256"
