#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/Codex\ Toolbox.app /path/to/output.pkg" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"

APP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_PKG="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
PKG_SCRIPTS="$ROOT_DIR/scripts/pkg/scripts"
BUILD_DIR="$(mktemp -d "${TMPDIR%/}/CodexToolbox-package.XXXXXX")"
COMPONENT_PKG="$BUILD_DIR/CodexToolbox-component.pkg"
PAYLOAD_ROOT="$BUILD_DIR/payload-root"

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing app bundle: $APP_PATH" >&2
    exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" != "io.github.zzzzzzjw.ShowCodexIQ" ]]; then
    echo "Unexpected app bundle identifier" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PKG")"
mkdir -p "$PAYLOAD_ROOT/Applications"
rm -f "$OUTPUT_PKG" "$OUTPUT_PKG.sha256"

ditto --noextattr --noqtn --noacl \
    "$APP_PATH" \
    "$PAYLOAD_ROOT/Applications/Codex Toolbox.app"
codesign --verify --deep --strict --verbose=2 \
    "$PAYLOAD_ROOT/Applications/Codex Toolbox.app"

/usr/bin/pkgbuild \
    --root "$PAYLOAD_ROOT" \
    --scripts "$PKG_SCRIPTS" \
    --identifier io.github.zzzzzzjw.CodexToolbox.pkg \
    --version "$RELEASE_VERSION" \
    --ownership recommended \
    "$COMPONENT_PKG"

if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
    /usr/bin/productbuild \
        --sign "$INSTALLER_SIGN_IDENTITY" \
        --package "$COMPONENT_PKG" \
        "$OUTPUT_PKG"
else
    /usr/bin/productbuild --package "$COMPONENT_PKG" "$OUTPUT_PKG"
    echo "Created an unsigned development PKG; Developer ID Installer signing is still required." >&2
fi

(
    cd "$(dirname "$OUTPUT_PKG")"
    /usr/bin/shasum -a 256 "$(basename "$OUTPUT_PKG")" > "$(basename "$OUTPUT_PKG").sha256"
)

echo "Created: $OUTPUT_PKG"
cat "$OUTPUT_PKG.sha256"
