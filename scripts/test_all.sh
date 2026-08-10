#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_APP="${XCODE_APP:-/Applications/Xcode-beta.app}"
SPM_SCRATCH=""
XCODE_DERIVED=""
TEST_APP=""
TEST_EXECUTABLE=""
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup() {
    if [[ -n "$TEST_EXECUTABLE" ]] && pgrep -f "$TEST_EXECUTABLE" >/dev/null 2>&1; then
        pkill -TERM -f "$TEST_EXECUTABLE" >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5; do
            if ! pgrep -f "$TEST_EXECUTABLE" >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
        pkill -KILL -f "$TEST_EXECUTABLE" >/dev/null 2>&1 || true
    fi

    if [[ -n "$TEST_APP" && -d "$TEST_APP" ]]; then
        "$LSREGISTER" -u "$TEST_APP" >/dev/null 2>&1 || true
    fi

    [[ -z "$SPM_SCRATCH" ]] || rm -rf "$SPM_SCRATCH"
    [[ -z "$XCODE_DERIVED" ]] || rm -rf "$XCODE_DERIVED"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SPM_SCRATCH="$(mktemp -d /private/tmp/CodexToolbox-spm-tests.XXXXXX)"
XCODE_DERIVED="$(mktemp -d /private/tmp/CodexToolbox-xcode-tests.XXXXXX)"
TEST_APP="$XCODE_DERIVED/Build/Products/Debug/Codex Toolbox.app"
TEST_EXECUTABLE="$TEST_APP/Contents/MacOS/Codex Toolbox"

if [[ ! -x "$XCODE_APP/Contents/Developer/usr/bin/xcodebuild" ]]; then
    echo "Xcode not found at: $XCODE_APP" >&2
    exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required" >&2
    exit 1
fi

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
export TOOLCHAINS="${TOOLCHAINS:-com.apple.dt.toolchain.XcodeDefault}"

cd "$ROOT_DIR"
xcodegen generate
bash scripts/version.sh

xcrun --toolchain "$TOOLCHAINS" swift test \
    --scratch-path "$SPM_SCRATCH"
xcrun --toolchain "$TOOLCHAINS" swift run \
    --scratch-path "$SPM_SCRATCH" \
    CoreVerification
xcodebuild build \
    -project CodexToolbox.xcodeproj \
    -scheme CodexToolbox \
    -destination 'platform=macOS' \
    -derivedDataPath "$XCODE_DERIVED" \
    CODE_SIGNING_ALLOWED=NO
xcodebuild test \
    -project CodexToolbox.xcodeproj \
    -scheme CodexToolboxCoreTests \
    -destination 'platform=macOS' \
    -derivedDataPath "$XCODE_DERIVED" \
    CODE_SIGNING_ALLOWED=NO

echo "All tests passed; temporary Xcode products will now be unregistered and removed."
