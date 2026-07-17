#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"

PKG_PATH="${1:-$ROOT_DIR/dist/Codex-Toolbox-$RELEASE_VERSION-universal.pkg}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

REQUIRE_DISTRIBUTION_SIGNATURE=1 "$ROOT_DIR/scripts/verify_pkg.sh" "$PKG_PATH"
xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PKG_PATH"
xcrun stapler validate "$PKG_PATH"
spctl --assess --type install --verbose=4 "$PKG_PATH"

(
    cd "$(dirname "$PKG_PATH")"
    shasum -a 256 "$(basename "$PKG_PATH")" > "$(basename "$PKG_PATH").sha256"
)

echo "Signed, notarized, and stapled PKG is ready: $PKG_PATH"
