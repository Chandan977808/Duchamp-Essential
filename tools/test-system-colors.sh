#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_PALETTE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_PALETTE_TEST_DIR="$(mktemp -d -t duchamp-system-colors.XXXXXXXX)"
trap 'rm -f "$DUCHAMP_PALETTE_TEST_DIR/host-tests"; rmdir "$DUCHAMP_PALETTE_TEST_DIR"' EXIT

cargo test --manifest-path "$DUCHAMP_PALETTE_ROOT/Cargo.toml" \
    -p duchamp-essential-daemon system_colors::tests
rustc --edition=2024 --test "$DUCHAMP_PALETTE_ROOT/tools/tests/system-colors-host.rs" \
    -o "$DUCHAMP_PALETTE_TEST_DIR/host-tests"
"$DUCHAMP_PALETTE_TEST_DIR/host-tests"

cd "$DUCHAMP_PALETTE_ROOT/ui/flutter"
flutter test test/system_colors_test.dart test/system_colors_preview_test.dart \
    test/system_colors_monitor_test.dart test/backend_connection_test.dart
