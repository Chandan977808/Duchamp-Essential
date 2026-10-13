#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_MODULE_SOURCE="$DUCHAMP_PROJECT_ROOT/android/kernelsu-next"
DUCHAMP_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
DUCHAMP_STAMP="$(date +%Y%m%d-%H%M%S)"
DUCHAMP_BUILD_ROOT="$DUCHAMP_PROJECT_ROOT/out/kernelsu-next/$DUCHAMP_STAMP"
DUCHAMP_STAGE="$DUCHAMP_BUILD_ROOT/module"
DUCHAMP_APP_BUILD="$DUCHAMP_BUILD_ROOT/application"

DUCHAMP_VERSION="$(sed -n 's/^version=//p' "$DUCHAMP_MODULE_SOURCE/module.prop")"
DUCHAMP_ZIP_NAME="Duchamp-Essential-KernelSU-Next-Magisk-${DUCHAMP_VERSION}.zip"
DUCHAMP_ZIP="$DUCHAMP_BUILD_ROOT/$DUCHAMP_ZIP_NAME"
DUCHAMP_STABLE_ZIP="$DUCHAMP_PROJECT_ROOT/out/Duchamp-Essential-KernelSU-Next-Magisk.zip"

[ -n "${DUCHAMP_KEYSTORE:-}" ] || {
    echo "DUCHAMP_KEYSTORE is required for a distributable root module." >&2
    echo "Use one persistent signing key for every module update." >&2
    exit 1
}

DUCHAMP_NDK_VERSION="$(find "$DUCHAMP_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
DUCHAMP_NDK="$DUCHAMP_SDK_ROOT/ndk/$DUCHAMP_NDK_VERSION"
DUCHAMP_TOOLCHAIN="$DUCHAMP_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
DUCHAMP_STRIP="$DUCHAMP_TOOLCHAIN/llvm-strip"
DUCHAMP_BUILD_TOOLS="$(find "$DUCHAMP_SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
DUCHAMP_AAPT2="$DUCHAMP_SDK_ROOT/build-tools/$DUCHAMP_BUILD_TOOLS/aapt2"
DUCHAMP_APKSIGNER="$DUCHAMP_SDK_ROOT/build-tools/$DUCHAMP_BUILD_TOOLS/apksigner"
DUCHAMP_ZIPALIGN="$DUCHAMP_SDK_ROOT/build-tools/$DUCHAMP_BUILD_TOOLS/zipalign"

for DUCHAMP_TOOL in "$DUCHAMP_STRIP" "$DUCHAMP_AAPT2" "$DUCHAMP_APKSIGNER" "$DUCHAMP_ZIPALIGN"; do
    [ -x "$DUCHAMP_TOOL" ] || {
        echo "Missing Android build tool: $DUCHAMP_TOOL" >&2
        exit 1
    }
done

"$DUCHAMP_PROJECT_ROOT/tools/test-kernelsu-watchdog-lock.sh"
"$DUCHAMP_PROJECT_ROOT/tools/test-root-module-contract.sh"
"$DUCHAMP_PROJECT_ROOT/tools/test-release-sync.sh"

mkdir -p "$DUCHAMP_STAGE/bin" "$DUCHAMP_STAGE/app"

echo "===== DUCHAMP ESSENTIAL — KERNELSU NEXT + MAGISK MODULE ====="
echo "version=$DUCHAMP_VERSION"
echo "ndk=$DUCHAMP_NDK_VERSION"
echo "output=$DUCHAMP_ZIP"

DUCHAMP_BUILD_ONLY=1 \
DUCHAMP_OUTPUT_DIR="$DUCHAMP_APP_BUILD" \
    "$DUCHAMP_PROJECT_ROOT/build-and-install.sh"

DUCHAMP_APK="$DUCHAMP_APP_BUILD/Duchamp-Essential.apk"
DUCHAMP_DAEMON="$DUCHAMP_APP_BUILD/host-cargo/aarch64-linux-android/release/duchamp_daemon"
DUCHAMP_CTL="$DUCHAMP_APP_BUILD/host-cargo/aarch64-linux-android/release/duchamp_ctl"

for DUCHAMP_ARTIFACT in "$DUCHAMP_APK" "$DUCHAMP_DAEMON" "$DUCHAMP_CTL"; do
    [ -f "$DUCHAMP_ARTIFACT" ] || {
        echo "Missing release artifact: $DUCHAMP_ARTIFACT" >&2
        exit 1
    }
done

install -m 0644 "$DUCHAMP_MODULE_SOURCE/module.prop" "$DUCHAMP_STAGE/module.prop"
install -m 0755 "$DUCHAMP_MODULE_SOURCE/customize.sh" "$DUCHAMP_STAGE/customize.sh"
install -m 0755 "$DUCHAMP_MODULE_SOURCE/service.sh" "$DUCHAMP_STAGE/service.sh"
install -m 0755 "$DUCHAMP_MODULE_SOURCE/action.sh" "$DUCHAMP_STAGE/action.sh"
install -m 0755 "$DUCHAMP_MODULE_SOURCE/uninstall.sh" "$DUCHAMP_STAGE/uninstall.sh"
install -m 0644 "$DUCHAMP_MODULE_SOURCE/skip_mount" "$DUCHAMP_STAGE/skip_mount"
install -m 0644 "$DUCHAMP_APK" "$DUCHAMP_STAGE/app/DuchampEssential.apk"
install -m 0755 "$DUCHAMP_DAEMON" "$DUCHAMP_STAGE/bin/duchamp_daemon"
install -m 0755 "$DUCHAMP_CTL" "$DUCHAMP_STAGE/bin/duchamp_ctl"

"$DUCHAMP_STRIP" --strip-unneeded "$DUCHAMP_STAGE/bin/duchamp_daemon"
"$DUCHAMP_STRIP" --strip-unneeded "$DUCHAMP_STAGE/bin/duchamp_ctl"

for DUCHAMP_SCRIPT in customize.sh service.sh action.sh uninstall.sh; do
    bash -n "$DUCHAMP_STAGE/$DUCHAMP_SCRIPT"
    if LC_ALL=C grep -q $'\r' "$DUCHAMP_STAGE/$DUCHAMP_SCRIPT"; then
        echo "CRLF line endings are not allowed: $DUCHAMP_SCRIPT" >&2
        exit 1
    fi
done

grep -Fxq 'export DUCHAMP_REVERSE_IPC=1' "$DUCHAMP_STAGE/service.sh" || {
    echo "Missing authenticated reverse IPC activation" >&2
    exit 1
}
grep -Fxq 'export DUCHAMP_LOOPBACK_IPC=1' "$DUCHAMP_STAGE/service.sh" || {
    echo "Missing authenticated loopback IPC activation" >&2
    exit 1
}
grep -Fq 'touch_resampler_ready' "$DUCHAMP_STAGE/action.sh" || {
    echo "Missing v1.18.0 touch-resampler diagnostics" >&2
    exit 1
}
grep -Fq 'App IPC: verified (daemon-initiated)' "$DUCHAMP_STAGE/action.sh" || {
    echo "Module Action does not verify the Android app transport" >&2
    exit 1
}
grep -Fq 'App IPC: verified (authenticated loopback)' "$DUCHAMP_STAGE/action.sh" || {
    echo "Module Action does not report the authenticated loopback transport" >&2
    exit 1
}
grep -Fq 'DUCHAMP_MODULE_MODE rom_native_update' "$DUCHAMP_STAGE/service.sh" || {
    echo "Missing ROM-native daemon takeover path" >&2
    exit 1
}
grep -Fq 'uninstall-system-updates "$DUCHAMP_PACKAGE"' "$DUCHAMP_STAGE/uninstall.sh" || {
    echo "Missing ROM-native application rollback path" >&2
    exit 1
}

DUCHAMP_MODID="$(sed -n 's/^id=//p' "$DUCHAMP_STAGE/module.prop")"
DUCHAMP_VERSION_CODE="$(sed -n 's/^versionCode=//p' "$DUCHAMP_STAGE/module.prop")"
[[ "$DUCHAMP_MODID" =~ ^[a-zA-Z][a-zA-Z0-9._-]+$ ]] || {
    echo "Invalid KernelSU module id: $DUCHAMP_MODID" >&2
    exit 1
}
[[ "$DUCHAMP_VERSION_CODE" =~ ^[0-9]+$ ]] || {
    echo "Invalid KernelSU versionCode: $DUCHAMP_VERSION_CODE" >&2
    exit 1
}

DUCHAMP_APK_BADGING="$("$DUCHAMP_AAPT2" dump badging "$DUCHAMP_STAGE/app/DuchampEssential.apk")"
DUCHAMP_APK_HEADER="$(printf '%s\n' "$DUCHAMP_APK_BADGING" | sed -n '1p')"
DUCHAMP_APK_PACKAGE="$(printf '%s\n' "$DUCHAMP_APK_HEADER" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
DUCHAMP_APK_VERSION_CODE="$(printf '%s\n' "$DUCHAMP_APK_HEADER" | sed -n "s/^package: name='[^']*' versionCode='\([^']*\)'.*/\1/p")"
DUCHAMP_APK_VERSION_NAME="$(printf '%s\n' "$DUCHAMP_APK_HEADER" | sed -n "s/^package: name='[^']*' versionCode='[^']*' versionName='\([^']*\)'.*/\1/p")"

[ "$DUCHAMP_APK_PACKAGE" = "com.saan.duchamp.essential" ] || {
    echo "Unexpected APK package: $DUCHAMP_APK_PACKAGE" >&2
    exit 1
}
[ "$DUCHAMP_APK_VERSION_CODE" = "$DUCHAMP_VERSION_CODE" ] || {
    echo "APK/module versionCode mismatch: $DUCHAMP_APK_VERSION_CODE / $DUCHAMP_VERSION_CODE" >&2
    exit 1
}
[ "$DUCHAMP_APK_VERSION_NAME" = "${DUCHAMP_VERSION#v}" ] || {
    echo "APK/module version mismatch: $DUCHAMP_APK_VERSION_NAME / $DUCHAMP_VERSION" >&2
    exit 1
}

"$DUCHAMP_APKSIGNER" verify --verbose "$DUCHAMP_STAGE/app/DuchampEssential.apk" >/dev/null
DUCHAMP_CERT_DIGEST="$("$DUCHAMP_APKSIGNER" verify --print-certs \
    "$DUCHAMP_STAGE/app/DuchampEssential.apk" \
    | sed -n 's/^.*certificate SHA-256 digest: //p' | head -n 1 \
    | tr '[:upper:]' '[:lower:]')"
DUCHAMP_EXPECTED_CERT_DIGEST="$(tr -d '[:space:]:' \
    <"$DUCHAMP_PROJECT_ROOT/android/package/release-cert.sha256" \
    | tr '[:upper:]' '[:lower:]')"
[[ "$DUCHAMP_CERT_DIGEST" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Unable to read APK signing certificate" >&2
    exit 1
}
[ "$DUCHAMP_CERT_DIGEST" = "$DUCHAMP_EXPECTED_CERT_DIGEST" ] || {
    if [ -n "${DUCHAMP_ALLOW_ANY_CERT:-}" ]; then
        echo "WARNING: skipping pinned release-certificate check (DUCHAMP_ALLOW_ANY_CERT is set)" >&2
        echo "This module is NOT signed with the pinned release key and will not update over official builds." >&2
    else
        echo "Official release certificate mismatch" >&2
        echo "expected=$DUCHAMP_EXPECTED_CERT_DIGEST" >&2
        echo "actual=$DUCHAMP_CERT_DIGEST" >&2
        exit 1
    fi
}
"$DUCHAMP_ZIPALIGN" -c -P 16 -v 4 "$DUCHAMP_STAGE/app/DuchampEssential.apk" >/dev/null
ANDROID_SDK_ROOT="$DUCHAMP_SDK_ROOT" bash "$DUCHAMP_PROJECT_ROOT/tools/check-platform-dex.sh" "$DUCHAMP_STAGE/app/DuchampEssential.apk"

file "$DUCHAMP_STAGE/bin/duchamp_daemon" | grep -q 'ARM aarch64'
file "$DUCHAMP_STAGE/bin/duchamp_ctl" | grep -q 'ARM aarch64'
readelf -lW "$DUCHAMP_STAGE/bin/duchamp_daemon" | grep -q '/system/bin/linker64'
readelf -lW "$DUCHAMP_STAGE/bin/duchamp_ctl" | grep -q '/system/bin/linker64'

for DUCHAMP_BINARY in "$DUCHAMP_STAGE/bin/duchamp_daemon" "$DUCHAMP_STAGE/bin/duchamp_ctl"; do
    DUCHAMP_LOAD_COUNT=0
    while read -r DUCHAMP_ALIGNMENT; do
        [ -n "$DUCHAMP_ALIGNMENT" ] || continue
        DUCHAMP_LOAD_COUNT=$((DUCHAMP_LOAD_COUNT + 1))
        if [ "$((DUCHAMP_ALIGNMENT))" -lt 16384 ]; then
            echo "ELF alignment below 16 KB: $DUCHAMP_BINARY ($DUCHAMP_ALIGNMENT)" >&2
            exit 1
        fi
    done < <(readelf -lW "$DUCHAMP_BINARY" | awk '$1 == "LOAD" { print $NF }')

    [ "$DUCHAMP_LOAD_COUNT" -gt 0 ] || {
        echo "No ELF LOAD segments found: $DUCHAMP_BINARY" >&2
        exit 1
    }
done

(
    cd "$DUCHAMP_STAGE"
    zip -X -9 "$DUCHAMP_ZIP" \
        module.prop customize.sh service.sh action.sh uninstall.sh skip_mount \
        app/DuchampEssential.apk bin/duchamp_daemon bin/duchamp_ctl >/dev/null
)

unzip -tq "$DUCHAMP_ZIP"
DUCHAMP_ENTRIES="$(unzip -Z1 "$DUCHAMP_ZIP")"
for DUCHAMP_REQUIRED in \
    module.prop customize.sh service.sh action.sh uninstall.sh skip_mount \
    app/DuchampEssential.apk bin/duchamp_daemon bin/duchamp_ctl; do
    echo "$DUCHAMP_ENTRIES" | grep -Fxq "$DUCHAMP_REQUIRED" || {
        echo "Missing module entry: $DUCHAMP_REQUIRED" >&2
        exit 1
    }
done

if echo "$DUCHAMP_ENTRIES" | grep -Eq '(^|/)system/'; then
    echo "Unexpected system overlay in the root module" >&2
    exit 1
fi
if echo "$DUCHAMP_ENTRIES" | grep -Eq '(^|/)(sepolicy\.rule|apply-sepolicy\.sh)$'; then
    echo "Unexpected SELinux patch payload in the root module" >&2
    exit 1
fi

DUCHAMP_STAGE_APK_SHA="$(sha256sum "$DUCHAMP_STAGE/app/DuchampEssential.apk" | awk '{print $1}')"
DUCHAMP_ZIP_APK_SHA="$(unzip -p "$DUCHAMP_ZIP" app/DuchampEssential.apk | sha256sum | awk '{print $1}')"
[ "$DUCHAMP_STAGE_APK_SHA" = "$DUCHAMP_ZIP_APK_SHA" ] || {
    echo "APK payload checksum mismatch" >&2
    exit 1
}

cp -f "$DUCHAMP_ZIP" "$DUCHAMP_STABLE_ZIP"
DUCHAMP_ZIP_SHA256="$(sha256sum "$DUCHAMP_ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$DUCHAMP_ZIP_SHA256" "${DUCHAMP_ZIP##*/}" \
    | tee "$DUCHAMP_ZIP.sha256"

echo "ROOT_MODULE=PASS"
echo "MANAGERS=KernelSU Next, Magisk"
echo "APK_PACKAGE=$DUCHAMP_APK_PACKAGE"
echo "APK_VERSION=$DUCHAMP_APK_VERSION_NAME ($DUCHAMP_APK_VERSION_CODE)"
echo "APK_CERT_SHA256=$DUCHAMP_CERT_DIGEST"
echo "ZIP=$DUCHAMP_ZIP"
echo "STABLE_ZIP=$DUCHAMP_STABLE_ZIP"
