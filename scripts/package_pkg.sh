#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/to/Codex\ Toolbox.app /path/to/output.pkg" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"
PACKAGE_VERSION="${PACKAGE_VERSION:-$RELEASE_VERSION}"

APP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_PKG="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
PKG_SCRIPTS="$ROOT_DIR/scripts/pkg/scripts"
BUILD_DIR="$(mktemp -d "${TMPDIR%/}/CodexToolbox-package.XXXXXX")"
COMPONENT_PKG="$BUILD_DIR/CodexToolbox-component.pkg"
DISTRIBUTION_XML="$BUILD_DIR/Distribution.xml"
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
    --version "$PACKAGE_VERSION" \
    --ownership recommended \
    "$COMPONENT_PKG"

/usr/bin/productbuild \
    --synthesize \
    --package "$COMPONENT_PKG" \
    "$DISTRIBUTION_XML"

# A synthesized distribution has no product title, which makes Installer show
# an empty pair of quotation marks in its localized welcome sentence.
/usr/bin/sed -i '' '/<installer-gui-script /a\
    <title>Codex Toolbox</title>\
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
' "$DISTRIBUTION_XML"

if [[ "$(/usr/bin/xmllint --xpath 'string(/installer-gui-script/title)' "$DISTRIBUTION_XML")" != "Codex Toolbox" ]]; then
    echo "Failed to set the Installer product title" >&2
    exit 1
fi

if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
    /usr/bin/productbuild \
        --sign "$INSTALLER_SIGN_IDENTITY" \
        --distribution "$DISTRIBUTION_XML" \
        --package-path "$BUILD_DIR" \
        "$OUTPUT_PKG"
else
    /usr/bin/productbuild \
        --distribution "$DISTRIBUTION_XML" \
        --package-path "$BUILD_DIR" \
        "$OUTPUT_PKG"
    echo "Created an unsigned development PKG; Developer ID Installer signing is still required." >&2
fi

(
    cd "$(dirname "$OUTPUT_PKG")"
    /usr/bin/shasum -a 256 "$(basename "$OUTPUT_PKG")" > "$(basename "$OUTPUT_PKG").sha256"
)

echo "Created: $OUTPUT_PKG"
cat "$OUTPUT_PKG.sha256"
