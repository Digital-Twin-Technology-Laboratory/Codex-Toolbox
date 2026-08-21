#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/version.sh"

TEAM_ID="${CODEX_TOOLBOX_SIGNING_TEAM_ID:-R9PVW8HZY2}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-Developer ID Application: Jiawei Zhang ($TEAM_ID)}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-Developer ID Installer: Jiawei Zhang ($TEAM_ID)}"
OUTPUT_PKG="${OUTPUT_PKG:-$ROOT_DIR/dist/Codex-Toolbox-$RELEASE_VERSION-Build$BUILD_NUMBER-local-test-universal.pkg}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$APP_SIGN_IDENTITY\""; then
    echo "Developer ID Application identity is unavailable: $APP_SIGN_IDENTITY" >&2
    exit 1
fi

if ! security find-identity -v -p basic | grep -Fq "\"$INSTALLER_SIGN_IDENTITY\""; then
    echo "Developer ID Installer identity is unavailable: $INSTALLER_SIGN_IDENTITY" >&2
    exit 1
fi

env \
    APP_SIGN_IDENTITY="$APP_SIGN_IDENTITY" \
    INSTALLER_SIGN_IDENTITY="$INSTALLER_SIGN_IDENTITY" \
    REQUIRE_DISTRIBUTION_SIGNATURE=1 \
    OUTPUT_PKG="$OUTPUT_PKG" \
    "$ROOT_DIR/scripts/build_pkg.sh"

echo "Signed local-test package ready: $OUTPUT_PKG"
