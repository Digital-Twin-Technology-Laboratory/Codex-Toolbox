#!/bin/bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 /path/to/App.app /path/to/output.dmg 'Volume Name'" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_DMG="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
VOL_NAME="$3"
BACKGROUND_SOURCE="$ROOT_DIR/design/dmg/ShowCodexIQ-dmg-background.png"
GUIDE_SOURCE="$ROOT_DIR/docs/distribution/首次打开说明.txt"
BUILD_DIR="${TMPDIR%/}/ShowCodexIQ-package-dmg-$$"
STAGE_DIR="$BUILD_DIR/dmg-root"
RW_DMG="$BUILD_DIR/ShowCodexIQ-installer-rw.dmg"
BUILD_VOL_NAME="Show Codex IQ Build $$"
DEVICE=""

cleanup() {
    if [[ -n "$DEVICE" ]]; then
        diskutil eject "$DEVICE" >/dev/null 2>&1 || true
    fi
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing app bundle: $APP_PATH" >&2
    exit 1
fi

if [[ ! -f "$BACKGROUND_SOURCE" ]]; then
    echo "Missing DMG background: $BACKGROUND_SOURCE" >&2
    exit 1
fi

if [[ ! -f "$GUIDE_SOURCE" ]]; then
    echo "Missing first-launch guide: $GUIDE_SOURCE" >&2
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$STAGE_DIR/.background" "$(dirname "$OUTPUT_DMG")"

ditto --noextattr --noqtn --noacl "$APP_PATH" "$STAGE_DIR/Show Codex IQ.app"
ln -s /Applications "$STAGE_DIR/Applications"
ditto --noextattr --noqtn --noacl "$GUIDE_SOURCE" "$STAGE_DIR/首次打开说明.txt"
ditto --noextattr --noqtn --noacl \
    "$BACKGROUND_SOURCE" \
    "$STAGE_DIR/.background/ShowCodexIQ-dmg-background.png"
codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/Show Codex IQ.app"

rm -f "$OUTPUT_DMG" "$OUTPUT_DMG.sha256" "$RW_DMG"
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
    "$OUTPUT_DMG"

(
    cd "$(dirname "$OUTPUT_DMG")"
    shasum -a 256 "$(basename "$OUTPUT_DMG")" > "$(basename "$OUTPUT_DMG").sha256"
)

echo "Created: $OUTPUT_DMG"
cat "$OUTPUT_DMG.sha256"
