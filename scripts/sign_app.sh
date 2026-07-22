#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/Codex\ Toolbox.app 'Developer ID Application: ...'" >&2
    echo "Use - as the identity for an ad-hoc development build." >&2
    exit 2
fi

APP_PATH="$1"
SIGN_IDENTITY="$2"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"

test -d "$APP_PATH"
test -d "$SPARKLE_FRAMEWORK"

sign_runtime() {
    local target="$1"
    shift
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        codesign --force --options runtime --sign - --timestamp=none "$@" "$target"
    else
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@" "$target"
    fi
}

# Sparkle's nested code must be signed from the inside out. In particular,
# Downloader.xpc keeps its network entitlement; using codesign --deep here
# would apply the wrong entitlements and can make the updater fail at runtime.
sign_runtime "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
sign_runtime "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
sign_runtime "$SPARKLE_VERSION_DIR/Autoupdate"
sign_runtime "$SPARKLE_VERSION_DIR/Updater.app"
sign_runtime "$SPARKLE_FRAMEWORK"
for embedded_dylib in "$APP_PATH"/Contents/MacOS/*.dylib; do
    if [[ -f "$embedded_dylib" ]]; then
        sign_runtime "$embedded_dylib"
    fi
done
sign_runtime "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
