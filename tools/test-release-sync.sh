#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_MODULE="$DUCHAMP_ROOT/android/kernelsu-next/module.prop"
DUCHAMP_MANIFEST="$DUCHAMP_ROOT/android/package/AndroidManifest.xml"
DUCHAMP_FLUTTER="$DUCHAMP_ROOT/ui/flutter/pubspec.yaml"
DUCHAMP_MAIN="$DUCHAMP_ROOT/ui/flutter/lib/main.dart"
DUCHAMP_DAEMON="$DUCHAMP_ROOT/runtime/daemon-rust/src/lib.rs"
DUCHAMP_HOST="$DUCHAMP_ROOT/runtime/host-rust/src/backend_bridge.rs"

DUCHAMP_CARGO_VERSION="$(sed -n 's/^version = "\([0-9][0-9.]*\)"$/\1/p' \
    "$DUCHAMP_ROOT/Cargo.toml" | head -n 1)"
DUCHAMP_MODULE_VERSION="$(sed -n 's/^version=v//p' "$DUCHAMP_MODULE")"
DUCHAMP_MODULE_CODE="$(sed -n 's/^versionCode=//p' "$DUCHAMP_MODULE")"
DUCHAMP_MANIFEST_VERSION="$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' \
    "$DUCHAMP_MANIFEST")"
DUCHAMP_MANIFEST_CODE="$(sed -n 's/.*android:versionCode="\([^"]*\)".*/\1/p' \
    "$DUCHAMP_MANIFEST")"
DUCHAMP_FLUTTER_VERSION="$(sed -n 's/^version: \([^+]*\)+.*/\1/p' "$DUCHAMP_FLUTTER")"
DUCHAMP_FLUTTER_CODE="$(sed -n 's/^version: [^+]*+\([0-9]*\).*/\1/p' "$DUCHAMP_FLUTTER")"
DUCHAMP_CHANGELOG_VERSION="$(sed -n 's/^## \([0-9][0-9.]*\)$/\1/p' \
    "$DUCHAMP_ROOT/CHANGELOG.md" | head -n 1)"

for DUCHAMP_VERSION in \
    "$DUCHAMP_MODULE_VERSION" "$DUCHAMP_MANIFEST_VERSION" \
    "$DUCHAMP_FLUTTER_VERSION" "$DUCHAMP_CHANGELOG_VERSION"; do
    [ "$DUCHAMP_VERSION" = "$DUCHAMP_CARGO_VERSION" ] || {
        echo "Release version mismatch: $DUCHAMP_VERSION / $DUCHAMP_CARGO_VERSION" >&2
        exit 1
    }
done

for DUCHAMP_CODE in "$DUCHAMP_MODULE_CODE" "$DUCHAMP_MANIFEST_CODE" "$DUCHAMP_FLUTTER_CODE"; do
    [ "$DUCHAMP_CODE" = "$DUCHAMP_MODULE_CODE" ] || {
        echo "Release versionCode mismatch: $DUCHAMP_CODE / $DUCHAMP_MODULE_CODE" >&2
        exit 1
    }
done

IFS=. read -r DUCHAMP_MAJOR DUCHAMP_MINOR DUCHAMP_PATCH <<EOF
$DUCHAMP_CARGO_VERSION
EOF
DUCHAMP_EXPECTED_CODE="$(printf '%d%02d%02d' \
    "$DUCHAMP_MAJOR" "$DUCHAMP_MINOR" "$DUCHAMP_PATCH")"
[ "$DUCHAMP_MODULE_CODE" = "$DUCHAMP_EXPECTED_CODE" ] || {
    echo "Release versionCode is not derived from the semantic version" >&2
    exit 1
}

grep -Fq "const String duchampVersionName = '$DUCHAMP_CARGO_VERSION';" \
    "$DUCHAMP_ROOT/ui/flutter/lib/release_identity.dart" && \
grep -Fq "const int duchampVersionCode = $DUCHAMP_MODULE_CODE;" \
    "$DUCHAMP_ROOT/ui/flutter/lib/release_identity.dart" && \
grep -Fq "version: 'v\$duchampVersionName'" "$DUCHAMP_MAIN" || {
    echo "In-app release label is not synchronized" >&2
    exit 1
}

DUCHAMP_DAEMON_SOCKET="$(sed -n 's/^pub const SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$DUCHAMP_DAEMON")"
DUCHAMP_HOST_SOCKET="$(sed -n 's/^const SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$DUCHAMP_HOST")"
DUCHAMP_DAEMON_REVERSE="$(sed -n 's/^pub const REVERSE_SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$DUCHAMP_DAEMON")"
DUCHAMP_HOST_REVERSE="$(sed -n 's/^const REVERSE_SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$DUCHAMP_HOST")"
DUCHAMP_PROTOCOL="$(sed -n 's/^pub const PROTOCOL_VERSION: &str = "\([^"]*\)";/\1/p' \
    "$DUCHAMP_DAEMON")"

[ -n "$DUCHAMP_DAEMON_SOCKET" ] && [ "$DUCHAMP_DAEMON_SOCKET" = "$DUCHAMP_HOST_SOCKET" ] || {
    echo "App/daemon primary socket mismatch" >&2
    exit 1
}
[ -n "$DUCHAMP_DAEMON_REVERSE" ] && [ "$DUCHAMP_DAEMON_REVERSE" = "$DUCHAMP_HOST_REVERSE" ] || {
    echo "App/daemon reverse socket mismatch" >&2
    exit 1
}
grep -Fq "Some(\"$DUCHAMP_PROTOCOL\")" "$DUCHAMP_HOST" || {
    echo "App/daemon protocol mismatch" >&2
    exit 1
}

for DUCHAMP_PACKAGER in \
    "$DUCHAMP_ROOT/tools/build-kernelsu-next-module.sh" \
    "$DUCHAMP_ROOT/tools/export-aosp-bundle.sh"; do
    grep -Fq 'build-and-install.sh' "$DUCHAMP_PACKAGER"
    grep -Fq 'Duchamp-Essential.apk' "$DUCHAMP_PACKAGER"
    grep -Fq 'host-cargo/aarch64-linux-android/release/duchamp_daemon' "$DUCHAMP_PACKAGER"
    grep -Fq -- '--strip-unneeded' "$DUCHAMP_PACKAGER"
done

echo 'RELEASE_SYNC_CONTRACT_TEST=PASS'
