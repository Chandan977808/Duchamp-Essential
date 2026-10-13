#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_MODULE="$DUCHAMP_PROJECT_ROOT/android/kernelsu-next"
DUCHAMP_SERVICE="$DUCHAMP_MODULE/service.sh"
DUCHAMP_INSTALLER="$DUCHAMP_MODULE/customize.sh"
DUCHAMP_ACTION="$DUCHAMP_MODULE/action.sh"

for DUCHAMP_SCRIPT in customize.sh service.sh action.sh uninstall.sh; do
    bash -n "$DUCHAMP_MODULE/$DUCHAMP_SCRIPT"
    if LC_ALL=C grep -q $'\r' "$DUCHAMP_MODULE/$DUCHAMP_SCRIPT"; then
        echo "CRLF line endings are not allowed: $DUCHAMP_SCRIPT" >&2
        exit 1
    fi
done

[ -f "$DUCHAMP_MODULE/skip_mount" ] || {
    echo "Root module must remain script-only and skip system mounting" >&2
    exit 1
}

if find "$DUCHAMP_MODULE" -maxdepth 1 -type f \
    \( -name 'sepolicy.rule' -o -name 'apply-sepolicy.sh' \) | grep -q .; then
    echo "Root module must not depend on app-to-root SELinux relaxation" >&2
    exit 1
fi

if grep -ERq 'magiskpolicy|ksud[[:space:]]+sepolicy|allow[[:space:]]+appdomain' \
    "$DUCHAMP_MODULE"; then
    echo "Root module contains an obsolete SELinux patch path" >&2
    exit 1
fi

grep -Fxq 'export DUCHAMP_REVERSE_IPC=1' "$DUCHAMP_SERVICE"
grep -Fxq 'export DUCHAMP_LOOPBACK_IPC=1' "$DUCHAMP_SERVICE"
grep -Fq 'export DUCHAMP_APP_UID' "$DUCHAMP_SERVICE"
grep -Fq 'pm list packages -U' "$DUCHAMP_SERVICE"
grep -Fq 'sys.boot_completed' "$DUCHAMP_SERVICE"
grep -Fq 'DUCHAMP_NATIVE_STATE_ROOT=/data/system/duchamp-essential' "$DUCHAMP_SERVICE"
grep -Fq 'DUCHAMP_MODULE_MODE rom_native_update' "$DUCHAMP_SERVICE"
grep -Fq 'ctl.stop' "$DUCHAMP_SERVICE"
grep -Fq 'rom-native-mode' "$DUCHAMP_INSTALLER"
grep -Fq 'update layer over the ROM-native installation' "$DUCHAMP_INSTALLER"
grep -Fq 'uninstall-system-updates "$DUCHAMP_PACKAGE"' "$DUCHAMP_MODULE/uninstall.sh"
grep -Fq 'ctl.start' "$DUCHAMP_MODULE/uninstall.sh"
grep -Fq 'App IPC: verified (daemon-initiated)' "$DUCHAMP_ACTION"
grep -Fq 'App IPC: verified (authenticated loopback)' "$DUCHAMP_ACTION"
grep -Fq 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' "$DUCHAMP_INSTALLER"
grep -Fq 'App/module version mismatch' "$DUCHAMP_INSTALLER"
grep -Fq 'touch_resampler_ready' "$DUCHAMP_ACTION"
[ -s "$DUCHAMP_PROJECT_ROOT/runtime/daemon-rust/src/touch_resampler.rs" ] || {
    echo "The v1.18.0 touch resampler source is missing" >&2
    exit 1
}

grep -Fq 'DUCHAMP_INSTALL_RESULT' "$DUCHAMP_INSTALLER"
grep -Fq 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' "$DUCHAMP_INSTALLER"
grep -Fq '/system/bin/pm uninstall "$DUCHAMP_PACKAGE"' "$DUCHAMP_INSTALLER"
grep -Fq 'if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ]' "$DUCHAMP_INSTALLER"
grep -Fq 'Application-local preferences were reset once' "$DUCHAMP_INSTALLER"

if grep -Fq '/system/bin/pm uninstall -k' "$DUCHAMP_INSTALLER"; then
    echo "Signature migration must not retain the obsolete package signing record" >&2
    exit 1
fi

if grep -Fq 'ROM-native Duchamp Essential detected; do not install' "$DUCHAMP_INSTALLER"; then
    echo "Installer still rejects ROM-native updates" >&2
    exit 1
fi

DUCHAMP_MODULE_VERSION="$(sed -n 's/^version=v//p' "$DUCHAMP_MODULE/module.prop")"
DUCHAMP_MODULE_CODE="$(sed -n 's/^versionCode=//p' "$DUCHAMP_MODULE/module.prop")"
DUCHAMP_MANIFEST_VERSION="$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' \
    "$DUCHAMP_PROJECT_ROOT/android/package/AndroidManifest.xml")"
DUCHAMP_MANIFEST_CODE="$(sed -n 's/.*android:versionCode="\([^"]*\)".*/\1/p' \
    "$DUCHAMP_PROJECT_ROOT/android/package/AndroidManifest.xml")"
DUCHAMP_FLUTTER_VERSION="$(sed -n 's/^version: \([^+]*\)+.*/\1/p' \
    "$DUCHAMP_PROJECT_ROOT/ui/flutter/pubspec.yaml")"
DUCHAMP_FLUTTER_CODE="$(sed -n 's/^version: [^+]*+\([0-9]*\).*/\1/p' \
    "$DUCHAMP_PROJECT_ROOT/ui/flutter/pubspec.yaml")"

for DUCHAMP_VERSION in "$DUCHAMP_MODULE_VERSION" "$DUCHAMP_MANIFEST_VERSION" "$DUCHAMP_FLUTTER_VERSION"; do
    [ "$DUCHAMP_VERSION" = "$DUCHAMP_MODULE_VERSION" ] || {
        echo "Application/module version mismatch" >&2
        exit 1
    }
done
for DUCHAMP_CODE in "$DUCHAMP_MODULE_CODE" "$DUCHAMP_MANIFEST_CODE" "$DUCHAMP_FLUTTER_CODE"; do
    [ "$DUCHAMP_CODE" = "$DUCHAMP_MODULE_CODE" ] || {
        echo "Application/module versionCode mismatch" >&2
        exit 1
    }
done

echo 'ROOT_MODULE_CONTRACT_TEST=PASS'
