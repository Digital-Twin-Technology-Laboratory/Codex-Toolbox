#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_CONFIG="$ROOT_DIR/Sources/CodexToolbox/Config/Version.xcconfig"

read_setting() {
    local key="$1"
    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            print value
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$VERSION_CONFIG"
}

RELEASE_VERSION="$(read_setting CODEX_TOOLBOX_RELEASE_VERSION)"
MARKETING_VERSION="$(read_setting MARKETING_VERSION)"
BUILD_NUMBER="$(read_setting CURRENT_PROJECT_VERSION)"

semver_pattern='^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
if [[ ! "$RELEASE_VERSION" =~ $semver_pattern ]]; then
    echo "Invalid CODEX_TOOLBOX_RELEASE_VERSION: $RELEASE_VERSION" >&2
    exit 1
fi

semver_core="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
if [[ "$MARKETING_VERSION" != "$semver_core" ]]; then
    echo "MARKETING_VERSION must match SemVer core $semver_core, found $MARKETING_VERSION" >&2
    exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "CURRENT_PROJECT_VERSION must be a positive integer, found $BUILD_NUMBER" >&2
    exit 1
fi

export RELEASE_VERSION MARKETING_VERSION BUILD_NUMBER

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'Release version: %s\nMarketing version: %s\nBuild number: %s\n' \
        "$RELEASE_VERSION" "$MARKETING_VERSION" "$BUILD_NUMBER"
fi
