#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REVISION="b741e480e203f037ca726bc2a76d99a8e8668e66"
SHA256="d09b9f2e12f292006a438365a0e0786e8657531a005c13bed2cb9f5aaad5f22c"
RUST_VERSION="1.95.0"
SOURCE_DIR="$ROOT_DIR/.build/native-source"
WORKSPACE="$SOURCE_DIR/codex-$REVISION/codex-rs"
export CARGO_HOME="${CARGO_HOME:-$ROOT_DIR/.build/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$ROOT_DIR/.build/rustup}"
export PATH="$CARGO_HOME/bin:$PATH"
mkdir -p "$SOURCE_DIR"
if ! command -v rustup >/dev/null; then
    case "$(uname -m)" in arm64) HOST=aarch64-apple-darwin ;; x86_64) HOST=x86_64-apple-darwin ;; *) exit 1 ;; esac
    URL="https://static.rust-lang.org/rustup/dist/$HOST/rustup-init"
    curl -fsSL "$URL" -o "$SOURCE_DIR/rustup-init"
    curl -fsSL "$URL.sha256" -o "$SOURCE_DIR/rustup-init.sha256"
    EXPECTED="$(cut -d ' ' -f 1 "$SOURCE_DIR/rustup-init.sha256")"
    ACTUAL="$(shasum -a 256 "$SOURCE_DIR/rustup-init" | cut -d ' ' -f 1)"
    [[ "$EXPECTED" == "$ACTUAL" ]]
    chmod +x "$SOURCE_DIR/rustup-init"
    "$SOURCE_DIR/rustup-init" -y --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION"
fi
if ! rustup run "$RUST_VERSION" rustc --version >/dev/null 2>&1; then
    rustup toolchain install "$RUST_VERSION" --profile minimal
fi
if [[ ! -f "$WORKSPACE/Cargo.toml" ]]; then
    curl -fsSL --retry 3 "https://codeload.github.com/openai/codex/tar.gz/$REVISION" -o "$SOURCE_DIR/codex.tar.gz"
    [[ "$(shasum -a 256 "$SOURCE_DIR/codex.tar.gz" | cut -d ' ' -f 1)" == "$SHA256" ]]
    tar -xzf "$SOURCE_DIR/codex.tar.gz" -C "$SOURCE_DIR"
fi
python3 - "$WORKSPACE/Cargo.toml" <<'PY'
import sys
p=sys.argv[1];s=open(p).read()
if '"toolbox-native-analytics"' not in s:
    s=s.replace('members = [', 'members = [\n    "toolbox-native-analytics",', 1)
    open(p,'w').write(s)
PY
mkdir -p "$WORKSPACE/toolbox-native-analytics"
rsync -a --exclude Cargo.lock "$ROOT_DIR/NativeAnalytics/" "$WORKSPACE/toolbox-native-analytics/"
cp "$ROOT_DIR/NativeAnalytics/Cargo.lock" "$WORKSPACE/Cargo.lock"
if [[ "${1:-}" == "--test" ]]; then
    cargo +"$RUST_VERSION" test --manifest-path "$WORKSPACE/Cargo.toml" -p toolbox-native-analytics --locked
    exit
fi
for TARGET in aarch64-apple-darwin x86_64-apple-darwin; do
    if ! rustup target list --toolchain "$RUST_VERSION" --installed | grep -qx "$TARGET"; then
        rustup target add --toolchain "$RUST_VERSION" "$TARGET"
    fi
done
export MACOSX_DEPLOYMENT_TARGET=14.0
for TARGET in aarch64-apple-darwin x86_64-apple-darwin; do
    cargo +"$RUST_VERSION" build --manifest-path "$WORKSPACE/Cargo.toml" -p toolbox-native-analytics --locked --release --target "$TARGET"
done
mkdir -p "$ROOT_DIR/.build/native-analytics"
lipo -create "$WORKSPACE/target/aarch64-apple-darwin/release/toolbox-native-analytics" "$WORKSPACE/target/x86_64-apple-darwin/release/toolbox-native-analytics" -output "$ROOT_DIR/.build/native-analytics/toolbox-native-analytics"
if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${EXECUTABLE_FOLDER_PATH:-}" ]]; then
    mkdir -p "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
    cp "$ROOT_DIR/.build/native-analytics/toolbox-native-analytics" "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/"
    cp "$ROOT_DIR/NativeAnalytics/LICENSE-OpenAI" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/NativeAnalytics-LICENSE.txt"
    cp "$ROOT_DIR/NativeAnalytics/THIRD-PARTY-NOTICES.txt" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/NativeAnalytics-THIRD-PARTY-NOTICES.txt"
fi
