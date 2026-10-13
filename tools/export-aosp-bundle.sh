#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_STAMP="$(date +%Y%m%d-%H%M%S)"
DUCHAMP_DESTINATION="${1:-$DUCHAMP_ROOT/dist/aosp/DuchampEssential-$DUCHAMP_STAMP}"
DUCHAMP_BUILD_DIR="$DUCHAMP_ROOT/out/aosp-export/$DUCHAMP_STAMP/build"
DUCHAMP_TEMPLATE="$DUCHAMP_ROOT/android/aosp"
DUCHAMP_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
DUCHAMP_NDK_VERSION="$(find "$DUCHAMP_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 \
    -type d -printf '%f\n' | sort -V | tail -1)"
DUCHAMP_STRIP="$DUCHAMP_SDK_ROOT/ndk/$DUCHAMP_NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

[ -n "${DUCHAMP_KEYSTORE:-}" ] || {
    echo "DUCHAMP_KEYSTORE is required for a reproducibly signed AOSP bundle." >&2
    echo "ROM maintainers must keep the same private key for every update." >&2
    exit 1
}
[ -f "$DUCHAMP_KEYSTORE" ] || {
    echo "DUCHAMP_KEYSTORE does not exist: $DUCHAMP_KEYSTORE" >&2
    exit 1
}

for DUCHAMP_TOOL in openssl readelf sha256sum unzip; do
    command -v "$DUCHAMP_TOOL" >/dev/null 2>&1 || {
        echo "Missing AOSP export tool: $DUCHAMP_TOOL" >&2
        exit 1
    }
done
[ -x "$DUCHAMP_STRIP" ] || {
    echo "Missing Android LLVM strip tool: $DUCHAMP_STRIP" >&2
    exit 1
}

"$DUCHAMP_ROOT/tools/test-aosp-integration.sh"
"$DUCHAMP_ROOT/tools/test-release-sync.sh"

if [ -e "$DUCHAMP_DESTINATION" ]; then
    echo "Destination already exists: $DUCHAMP_DESTINATION" >&2
    exit 1
fi

DUCHAMP_BUILD_ONLY=1 \
DUCHAMP_OUTPUT_DIR="$DUCHAMP_BUILD_DIR" \
    "$DUCHAMP_ROOT/build-and-install.sh"

DUCHAMP_APK="$DUCHAMP_BUILD_DIR/Duchamp-Essential.apk"
DUCHAMP_DAEMON="$DUCHAMP_BUILD_DIR/host-cargo/aarch64-linux-android/release/duchamp_daemon"
DUCHAMP_CTL="$DUCHAMP_BUILD_DIR/host-cargo/aarch64-linux-android/release/duchamp_ctl"
DUCHAMP_BUILD_TOOLS="$(find "$DUCHAMP_SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
DUCHAMP_APKSIGNER="$DUCHAMP_SDK_ROOT/build-tools/$DUCHAMP_BUILD_TOOLS/apksigner"

[ -x "$DUCHAMP_APKSIGNER" ] || {
    echo "Missing Android APK signer: $DUCHAMP_APKSIGNER" >&2
    exit 1
}

for DUCHAMP_ARTIFACT in "$DUCHAMP_APK" "$DUCHAMP_DAEMON" "$DUCHAMP_CTL"; do
    [ -f "$DUCHAMP_ARTIFACT" ] || {
        echo "Missing AOSP artifact: $DUCHAMP_ARTIFACT" >&2
        exit 1
    }
done

mkdir -p "$DUCHAMP_DESTINATION/prebuilt" "$DUCHAMP_DESTINATION/docs"
cp -a "$DUCHAMP_TEMPLATE/Android.bp" "$DUCHAMP_DESTINATION/Android.bp"
cp -a "$DUCHAMP_TEMPLATE/duchamp-essential.mk" "$DUCHAMP_DESTINATION/duchamp-essential.mk"
cp -a "$DUCHAMP_TEMPLATE/BoardConfigDuchampEssential.mk" "$DUCHAMP_DESTINATION/BoardConfigDuchampEssential.mk"
cp -a "$DUCHAMP_TEMPLATE/duchamp_daemon.rc" "$DUCHAMP_DESTINATION/duchamp_daemon.rc"
cp -a "$DUCHAMP_TEMPLATE/sepolicy" "$DUCHAMP_DESTINATION/sepolicy"
cp -a "$DUCHAMP_TEMPLATE/README.md" "$DUCHAMP_DESTINATION/README.md"
cp -a "$DUCHAMP_ROOT/docs/ROM_INTEGRATION.md" "$DUCHAMP_DESTINATION/docs/ROM_INTEGRATION.md"
cp -a "$DUCHAMP_ROOT/docs/UNPACKED_ROM_INTEGRATION.md" "$DUCHAMP_DESTINATION/docs/UNPACKED_ROM_INTEGRATION.md"
cp -a "$DUCHAMP_ROOT/docs/UNPACKED_ROM_PORTER_GUIDE.md" "$DUCHAMP_DESTINATION/docs/UNPACKED_ROM_PORTER_GUIDE.md"
mkdir -p "$DUCHAMP_DESTINATION/tools"
cp -a "$DUCHAMP_ROOT/tools/prepare-aosp-touch-policy.py" "$DUCHAMP_DESTINATION/tools/prepare-aosp-touch-policy.py"
install -m 0644 "$DUCHAMP_APK" "$DUCHAMP_DESTINATION/prebuilt/DuchampEssential.apk"
install -m 0755 "$DUCHAMP_DAEMON" "$DUCHAMP_DESTINATION/prebuilt/duchamp_daemon"
install -m 0755 "$DUCHAMP_CTL" "$DUCHAMP_DESTINATION/prebuilt/duchamp_ctl"
"$DUCHAMP_STRIP" --strip-unneeded "$DUCHAMP_DESTINATION/prebuilt/duchamp_daemon"
"$DUCHAMP_STRIP" --strip-unneeded "$DUCHAMP_DESTINATION/prebuilt/duchamp_ctl"

"$DUCHAMP_APKSIGNER" verify --print-certs-pem "$DUCHAMP_APK" 2>/dev/null \
    | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
    >"$DUCHAMP_DESTINATION/prebuilt/DuchampEssential.x509.pem"
openssl x509 -in "$DUCHAMP_DESTINATION/prebuilt/DuchampEssential.x509.pem" \
    -noout -subject >/dev/null
DUCHAMP_APK_CERT_DIGEST="$("$DUCHAMP_APKSIGNER" verify --print-certs "$DUCHAMP_APK" \
    2>/dev/null | sed -n 's/^.*certificate SHA-256 digest: //p' | head -n 1 \
    | tr '[:upper:]' '[:lower:]')"
DUCHAMP_PEM_CERT_DIGEST="$(openssl x509 \
    -in "$DUCHAMP_DESTINATION/prebuilt/DuchampEssential.x509.pem" -outform DER \
    | sha256sum | awk '{print $1}')"
[[ "$DUCHAMP_APK_CERT_DIGEST" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Unable to read the exported APK certificate" >&2
    exit 1
}
[ "$DUCHAMP_APK_CERT_DIGEST" = "$DUCHAMP_PEM_CERT_DIGEST" ] || {
    echo "Exported APK and SELinux public certificate do not match" >&2
    exit 1
}
openssl x509 -in "$DUCHAMP_DESTINATION/prebuilt/DuchampEssential.x509.pem" \
    -noout -subject -issuer -dates -fingerprint -sha256 \
    >"$DUCHAMP_DESTINATION/SIGNING-CERTIFICATE.txt"

ANDROID_SDK_ROOT="$DUCHAMP_SDK_ROOT" bash "$DUCHAMP_ROOT/tools/check-platform-dex.sh" "$DUCHAMP_DESTINATION/prebuilt/DuchampEssential.apk"

file "$DUCHAMP_DESTINATION/prebuilt/duchamp_daemon" | grep -q 'ARM aarch64'
file "$DUCHAMP_DESTINATION/prebuilt/duchamp_ctl" | grep -q 'ARM aarch64'

DUCHAMP_DAEMON_NEEDED="$(readelf -d "$DUCHAMP_DESTINATION/prebuilt/duchamp_daemon" \
    | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | LC_ALL=C sort)"
DUCHAMP_CTL_NEEDED="$(readelf -d "$DUCHAMP_DESTINATION/prebuilt/duchamp_ctl" \
    | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | LC_ALL=C sort)"
DUCHAMP_EXPECTED_DAEMON_NEEDED=$'libbinder_ndk.so\nlibc.so\nlibdl.so'
DUCHAMP_EXPECTED_CTL_NEEDED=$'libc.so\nlibdl.so'
[ "$DUCHAMP_DAEMON_NEEDED" = "$DUCHAMP_EXPECTED_DAEMON_NEEDED" ] || {
    echo "duchamp_daemon dependencies do not match Android.bp" >&2
    printf '%s\n' "$DUCHAMP_DAEMON_NEEDED" >&2
    exit 1
}
[ "$DUCHAMP_CTL_NEEDED" = "$DUCHAMP_EXPECTED_CTL_NEEDED" ] || {
    echo "duchamp_ctl dependencies do not match Android.bp" >&2
    printf '%s\n' "$DUCHAMP_CTL_NEEDED" >&2
    exit 1
}

(
    cd "$DUCHAMP_DESTINATION"
    find . -type f ! -name SHA256SUMS -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum \
        > SHA256SUMS
)

echo "AOSP_EXPORT=PASS"
echo "APK_CERT_SHA256=$DUCHAMP_APK_CERT_DIGEST"
echo "DIRECTORY=$DUCHAMP_DESTINATION"
