#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
VERSION="$RELEASE_VERSION"
BUILD_DIR="${TMPDIR%/}/ShowCodexIQ-portable-dmg"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$BUILD_DIR/Show Codex IQ.app"
DMG_NAME="Show-Codex-IQ-$VERSION-universal-portable.dmg"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"

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

"$ROOT_DIR/scripts/package_dmg.sh" \
    "$APP_PATH" \
    "$DIST_DIR/$DMG_NAME" \
    "Show Codex IQ $VERSION"

echo "Created portable verification build: $DIST_DIR/$DMG_NAME"
echo "Architectures: $ARCHS"
