#!/bin/bash
# Build the Rust static library used by the Xcode target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SRCROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
RUST_DIR="$PROJECT_DIR/ahpc-rs"
LIB_NAME="libahpc.a"
TARGET="x86_64-apple-darwin"
DEST_DIR="$RUST_DIR/target/release"

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust or add it to PATH." >&2
  exit 1
fi

if [ ! -d "$RUST_DIR" ]; then
  echo "error: ahpc-rs submodule is missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi

echo "🔨 Building Rust static library ($TARGET)..."

cd "$RUST_DIR"

cargo build --release --locked --target "$TARGET" 2>&1 | sed "s/^/   [$TARGET] /"

mkdir -p "$DEST_DIR"
cp -f "$RUST_DIR/target/$TARGET/release/$LIB_NAME" "$DEST_DIR/$LIB_NAME"

echo "✅ Rust $TARGET build complete: $DEST_DIR/$LIB_NAME"
