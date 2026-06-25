#!/bin/bash
# Build Rust static library (x86_64 only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SRCROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
RUST_DIR="$PROJECT_DIR/ahpc-rs"
LIB_NAME="libahpc.a"

echo "🔨 Building Rust static library (x86_64)..."

cd "$RUST_DIR"

export PATH="$HOME/.cargo/bin:$PATH"
cargo build --release --target x86_64-apple-darwin 2>&1 | sed 's/^/   [x86_64] /'

cp "target/x86_64-apple-darwin/release/$LIB_NAME" "target/release/$LIB_NAME"

echo "✅ Rust x86_64 build complete: $RUST_DIR/target/release/$LIB_NAME"
