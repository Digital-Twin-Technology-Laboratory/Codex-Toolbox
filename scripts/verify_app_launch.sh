#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/Codex\ Toolbox.app" >&2
    exit 2
fi

APP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
EXECUTABLE="$APP_PATH/Contents/MacOS/Codex Toolbox"
SMOKE_DIR="$(mktemp -d "${TMPDIR%/}/CodexToolbox-launch-smoke.XXXXXX")"
SMOKE_PID=""

cleanup() {
    if [[ -n "$SMOKE_PID" ]] && kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
        kill "$SMOKE_PID" >/dev/null 2>&1 || true
        wait "$SMOKE_PID" >/dev/null 2>&1 || true
    fi
    rm -rf "$SMOKE_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

test -d "$APP_PATH"
test -x "$EXECUTABLE"

mkdir -p "$SMOKE_DIR/home"

run_launch_smoke_test() {
    local label="$1"
    local shows_trend_chart="$2"
    local stdout_log="$SMOKE_DIR/$label-stdout.log"
    local stderr_log="$SMOKE_DIR/$label-stderr.log"

    CFFIXED_USER_HOME="$SMOKE_DIR/home" \
        "$EXECUTABLE" \
        -showsTrendChart "$shows_trend_chart" \
        >"$stdout_log" \
        2>"$stderr_log" &
    SMOKE_PID=$!
    sleep 3

    # Validate only the exact child PID started from this packaged executable.
    # An installed copy may remain running without being mistaken for the
    # artifact under test or being terminated by cleanup.
    if ! kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
        wait "$SMOKE_PID" >/dev/null 2>&1 || true
        echo "App exited during the $label launch smoke test" >&2
        sed -n '1,120p' "$stderr_log" >&2
        exit 1
    fi

    kill "$SMOKE_PID" >/dev/null 2>&1 || true
    wait "$SMOKE_PID" >/dev/null 2>&1 || true
    SMOKE_PID=""
}

run_launch_smoke_test "trend-visible" true
run_launch_smoke_test "trend-hidden" false

echo "Launch smoke tests: passed"
