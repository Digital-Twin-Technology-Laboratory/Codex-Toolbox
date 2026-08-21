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

DISTRIBUTION_XML="$EXPANDED/Distribution"
test -f "$DISTRIBUTION_XML"
test "$(/usr/bin/xmllint --xpath 'string(/installer-gui-script/title)' "$DISTRIBUTION_XML")" = "Codex Toolbox"
test "$(/usr/bin/xmllint --xpath 'string(/installer-gui-script/domains/@enable_anywhere)' "$DISTRIBUTION_XML")" = "false"
test "$(/usr/bin/xmllint --xpath 'string(/installer-gui-script/domains/@enable_currentUserHome)' "$DISTRIBUTION_XML")" = "false"
test "$(/usr/bin/xmllint --xpath 'string(/installer-gui-script/domains/@enable_localSystem)' "$DISTRIBUTION_XML")" = "true"

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
test "$(plutil -extract SUEnableAutomaticChecks raw "$PLIST")" = true
test "$(plutil -extract SUAutomaticallyUpdate raw "$PLIST")" = true
test "$(plutil -extract SUScheduledCheckInterval raw "$PLIST")" = 86400
test "$(plutil -extract SUPublicEDKey raw "$PLIST")" = "$SPARKLE_PUBLIC_ED_KEY"
test -d "$APP_PATH/Contents/Frameworks/Sparkle.framework"

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
if ! otool -L "$EXECUTABLE" | grep -q 'Sparkle.framework'; then
    echo "Sparkle.framework must be linked for in-app updates" >&2
    exit 1
fi

test -x "$EXPANDED"/*/Scripts/preinstall
test -x "$EXPANDED"/*/Scripts/postinstall
grep -q 'launchctl asuser' "$EXPANDED"/*/Scripts/postinstall
grep -q 'successful interactive install always launches' "$EXPANDED"/*/Scripts/postinstall
if grep -q 'RELAUNCH_MARKER' "$EXPANDED"/*/Scripts/postinstall; then
    echo "The installer must launch after every successful interactive install" >&2
    exit 1
fi

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

    signature_team_id() {
        codesign -dvv "$1" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }'
    }

    APP_TEAM_ID="$(signature_team_id "$APP_PATH")"
    if [[ ! "$APP_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        echo "The app must have a valid signing Team ID, found: ${APP_TEAM_ID:-none}" >&2
        exit 1
    fi

    SPARKLE_VERSION_DIR="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
    SIGNED_TARGETS=(
        "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
        "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
        "$SPARKLE_VERSION_DIR/Autoupdate"
        "$SPARKLE_VERSION_DIR/Updater.app"
        "$APP_PATH/Contents/Frameworks/Sparkle.framework"
    )
    for signed_target in "${SIGNED_TARGETS[@]}"; do
        TARGET_TEAM_ID="$(signature_team_id "$signed_target")"
        if [[ "$TARGET_TEAM_ID" != "$APP_TEAM_ID" ]]; then
            echo "Signing Team ID mismatch: $signed_target uses ${TARGET_TEAM_ID:-none}, app uses $APP_TEAM_ID" >&2
            exit 1
        fi
    done
    for embedded_dylib in "$APP_PATH"/Contents/MacOS/*.dylib; do
        if [[ -f "$embedded_dylib" && "$(signature_team_id "$embedded_dylib")" != "$APP_TEAM_ID" ]]; then
            echo "Signing Team ID mismatch: $embedded_dylib" >&2
            exit 1
        fi
    done

    INSTALLER_TEAM_ID="$(
        grep -m1 'Developer ID Installer:' <<<"$SIGNATURE_OUTPUT" \
            | sed -E 's/.*\(([A-Z0-9]{10})\).*/\1/'
    )"
    if [[ "$INSTALLER_TEAM_ID" != "$APP_TEAM_ID" ]]; then
        echo "Installer Team ID $INSTALLER_TEAM_ID does not match app Team ID $APP_TEAM_ID" >&2
        exit 1
    fi
fi

if [[ -f "$PKG_PATH.sha256" ]]; then
    (cd "$(dirname "$PKG_PATH")" && shasum -a 256 -c "$(basename "$PKG_PATH").sha256")
fi

"$ROOT_DIR/scripts/verify_app_launch.sh" "$APP_PATH"

echo "PKG verified: $(basename "$PKG_PATH")"
echo "Architectures: $ARCHITECTURES"
if [[ -n "${APP_TEAM_ID:-}" ]]; then
    echo "Signing Team ID: $APP_TEAM_ID"
fi
if grep -q 'Developer ID Installer' <<<"$SIGNATURE_OUTPUT"; then
    echo "Installer signature: Developer ID Installer"
else
    echo "Installer signature: unsigned development artifact"
fi
