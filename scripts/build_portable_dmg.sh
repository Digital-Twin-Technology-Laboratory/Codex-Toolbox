#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.1.0-beta.1"
BUILD_DIR="${TMPDIR%/}/ShowCodexIQ-portable-dmg"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$BUILD_DIR/Show Codex IQ.app"
STAGE_DIR="$BUILD_DIR/dmg-root"
DMG_NAME="Show-Codex-IQ-$VERSION-universal-portable.dmg"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"

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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :ShowCodexIQReleaseVersion $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$PLIST"

ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$ROOT_DIR"/Sources/ShowCodexIQ/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
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

echo "Created portable verification build: $DIST_DIR/$DMG_NAME"
echo "Architectures: $ARCHS"
cat "$DIST_DIR/$DMG_NAME.sha256"
