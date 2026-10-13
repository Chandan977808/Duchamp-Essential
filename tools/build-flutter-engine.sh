#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_FLUTTER_BIN="$(command -v flutter 2>/dev/null || true)"

[ -n "$DUCHAMP_FLUTTER_BIN" ] || {
    echo "Flutter is not in PATH" >&2
    exit 1
}

DUCHAMP_FLUTTER_BIN="$(readlink -f "$DUCHAMP_FLUTTER_BIN")"
DUCHAMP_FLUTTER_ROOT="$(cd "$(dirname "$DUCHAMP_FLUTTER_BIN")/.." && pwd)"
DUCHAMP_ENGINE_SRC="${DUCHAMP_FLUTTER_ENGINE_SRC:-$DUCHAMP_FLUTTER_ROOT/engine/src}"
DUCHAMP_ENGINE_OUT="$DUCHAMP_ENGINE_SRC/out/android_release_arm64"
DUCHAMP_PREBUILT="$DUCHAMP_ROOT/runtime/flutter-engine/prebuilt/android-arm64"

[ -x "$DUCHAMP_ENGINE_SRC/flutter/tools/gn" ] || {
    echo "Flutter engine checkout not found: $DUCHAMP_ENGINE_SRC" >&2
    echo "Set DUCHAMP_FLUTTER_ENGINE_SRC to the engine src directory" >&2
    exit 1
}

command -v ninja >/dev/null 2>&1 || {
    echo "ninja is required" >&2
    exit 1
}

DUCHAMP_EXPECTED_REVISION="$(tr -d '[:space:]' <"$DUCHAMP_FLUTTER_ROOT/bin/internal/engine.version")"
DUCHAMP_ACTUAL_REVISION="$(git -C "$DUCHAMP_ENGINE_SRC" rev-parse HEAD 2>/dev/null || true)"

if [ -n "$DUCHAMP_ACTUAL_REVISION" ] && [ "$DUCHAMP_ACTUAL_REVISION" != "$DUCHAMP_EXPECTED_REVISION" ]; then
    echo "Flutter framework and engine revisions do not match" >&2
    echo "framework engine: $DUCHAMP_EXPECTED_REVISION" >&2
    echo "engine checkout:  $DUCHAMP_ACTUAL_REVISION" >&2
    exit 1
fi

(
    cd "$DUCHAMP_ENGINE_SRC"
    ./flutter/tools/gn \
        --android \
        --android-cpu arm64 \
        --runtime-mode release \
        --no-lto
)

ninja -C "$DUCHAMP_ENGINE_OUT" \
    flutter/shell/platform/embedder:flutter_engine_library

for DUCHAMP_ARTIFACT in \
    "$DUCHAMP_ENGINE_OUT/libflutter_engine.so" \
    "$DUCHAMP_ENGINE_OUT/icudtl.dat" \
    "$DUCHAMP_ENGINE_SRC/flutter/shell/platform/embedder/embedder.h"; do
    [ -f "$DUCHAMP_ARTIFACT" ] || {
        echo "Missing engine artifact: $DUCHAMP_ARTIFACT" >&2
        exit 1
    }
done

mkdir -p "$DUCHAMP_PREBUILT" "$DUCHAMP_ROOT/runtime/flutter-engine/include"
install -m 0644 "$DUCHAMP_ENGINE_OUT/libflutter_engine.so" "$DUCHAMP_PREBUILT/libflutter_engine.so"
install -m 0644 "$DUCHAMP_ENGINE_OUT/icudtl.dat" "$DUCHAMP_PREBUILT/icudtl.dat"
install -m 0644 \
    "$DUCHAMP_ENGINE_SRC/flutter/shell/platform/embedder/embedder.h" \
    "$DUCHAMP_ROOT/runtime/flutter-engine/include/embedder.h"

echo "FLUTTER_ENGINE_BUILD=PASS"
echo "ENGINE_REVISION=$DUCHAMP_EXPECTED_REVISION"
echo "PREBUILT_DIR=$DUCHAMP_PREBUILT"
