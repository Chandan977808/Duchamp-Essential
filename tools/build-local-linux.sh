#!/usr/bin/env bash
# Local workstation builder for Duchamp Essential (SaanOS port).
# Runs on Ubuntu 24.04 or WSL2-Ubuntu on Windows.
# Usage inside a git clone:   ./tools/build-local-linux.sh
# Usage with a tarball:       ./tools/build-local-linux.sh Duchamp-Essential-source.tar.gz
# Result: ~/duchamp-build/Duchamp-output/ with the module ZIP + AOSP bundle.
set -euo pipefail

WORK="$HOME/duchamp-build"
OUT="$WORK/Duchamp-output"
SDK="$HOME/Android/Sdk"

if [ -f ./tools/build-flutter-engine.sh ]; then
  PROJECT="$PWD"
  echo "Using current checkout: $PROJECT"
else
  SRC_TARBALL="${1:-./Duchamp-Essential-source.tar.gz}"
  [ -f "$SRC_TARBALL" ] || { echo "Missing $SRC_TARBALL" >&2; exit 1; }
  PROJECT="$WORK/Duchamp-Essential"
fi
mkdir -p "$WORK" "$OUT"

echo "===== 1. System tools ====="
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk ninja-build pkg-config curl unzip zip \
  python3 git

echo "===== 2. Flutter (stable) ====="
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
  git clone --depth 1 -b 3.47.7 https://github.com/flutter/flutter.git "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
flutter --version
ENGINE_REV="$(tr -d '[:space:]' <"$HOME/flutter/bin/internal/engine.version")"
echo "engine_rev=$ENGINE_REV"

echo "===== 3. Rust ====="
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi
rustup target add aarch64-linux-android

echo "===== 4. depot_tools (gclient) ====="
if [ ! -x "$WORK/depot_tools/gclient" ]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$WORK/depot_tools"
fi
export PATH="$WORK/depot_tools:$PATH"

echo "===== 5. Android SDK ====="
mkdir -p "$SDK/cmdline-tools"
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  for V in 11076708 10406996 9869600 9477386; do
    if curl -fL -o "$WORK/cmdtools.zip" \
      "https://dl.google.com/android/repository/commandlinetools-linux-${V}_latest.zip"; then
      echo "cmdline-tools build $V downloaded"
      break
    fi
  done
  [ -f "$WORK/cmdtools.zip" ] || { echo "cmdline-tools download failed" >&2; exit 1; }
  rm -rf "$SDK/cmdline-tools/latest"
  mkdir -p "$SDK/cmdline-tools/latest"
  unzip -q "$WORK/cmdtools.zip" -d "$SDK/cmdline-tools/latest"
  mv "$SDK/cmdline-tools/latest/cmdline-tools"/* "$SDK/cmdline-tools/latest/" 2>/dev/null || true
fi
export ANDROID_SDK_ROOT="$SDK"
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null 2>&1 || true
"$SDK/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "platforms;android-36"
BT="$("$SDK/cmdline-tools/latest/bin/sdkmanager" --list 2>/dev/null | grep -o 'build-tools;[0-9.]*' | sort -V | tail -1)"
NDK="$("$SDK/cmdline-tools/latest/bin/sdkmanager" --list 2>/dev/null | grep -o 'ndk;27\.[0-9.]*' | sort -V | tail -1)"
echo "Installing $BT and $NDK"
[ -n "${BT:-}" ] || { echo "No build-tools found" >&2; exit 1; }
[ -n "${NDK:-}" ] || { echo "No NDK r27 found" >&2; exit 1; }
"$SDK/cmdline-tools/latest/bin/sdkmanager" "$BT" "$NDK"

if [ "$PROJECT" = "$PWD" ]; then
  echo "===== Project sources: using current checkout ====="
else
  echo "===== Project sources: extracting tarball ====="
  rm -rf "$PROJECT"
  mkdir -p "$PROJECT"
  tar -xzf "$SRC_TARBALL" -C "$PROJECT" --strip-components=0
fi

echo "===== 7. Flutter engine sources + build ====="
cd "$HOME/flutter"
if [ ! -f .gclient ]; then
  cp engine/scripts/standard.gclient .gclient
fi
for i in 1 2 3; do
  if gclient sync; then break; fi
  echo "gclient sync attempt $i failed, retrying..."
  sleep 15
done
# engine/src is populated by gclient without git metadata; the engine build
# script skips its revision check in that case (it only enforces when the
# tree carries its own .git). Never git-checkout inside engine/src without
# its own .git: that would move the whole SDK checkout instead.
export DUCHAMP_FLUTTER_ENGINE_SRC="$HOME/flutter/engine/src"
"$PROJECT/tools/build-flutter-engine.sh"

echo "===== 8. Signing key (ONE key forever) ====="
if [ -f "$OUT/duchamp-release.jks" ]; then
  echo "Reusing existing $OUT/duchamp-release.jks"
else
  # shellcheck disable=SC2016
  STORE_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  KEY_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  keytool -genkeypair -keystore "$OUT/duchamp-release.jks" -alias duchamp-essential \
    -keyalg RSA -keysize 4096 -validity 9125 \
    -storepass "$STORE_PASS" -keypass "$KEY_PASS" \
    -dname "CN=SaanOS Duchamp Essential,O=SaanOS,C=US"
  printf 'alias: duchamp-essential\nstorepass: %s\nkeypass: %s\n' \
    "$STORE_PASS" "$KEY_PASS" > "$OUT/KEY.txt"
  echo "!!! BACK UP $OUT/duchamp-release.jks AND $OUT/KEY.txt — same key for every update !!!"
fi
if [ -f "$OUT/KEY.txt" ]; then
  # shellcheck disable=SC1091
  DUCHAMP_KEYSTORE_PASS="$(grep '^storepass:' "$OUT/KEY.txt" | cut -d' ' -f2)"
  DUCHAMP_KEY_PASS="$(grep '^keypass:' "$OUT/KEY.txt" | cut -d' ' -f2)"
  export DUCHAMP_KEYSTORE_PASS DUCHAMP_KEY_PASS
fi
export DUCHAMP_KEYSTORE="$OUT/duchamp-release.jks"
export DUCHAMP_KEY_ALIAS=duchamp-essential

echo "===== 9. Root module ZIP ====="
cd "$PROJECT"
./tools/build-kernelsu-next-module.sh
cp out/Duchamp-Essential-KernelSU-Next-Magisk.zip "$OUT/" 2>/dev/null || \
  cp out/kernelsu-next/*/*.zip "$OUT/" 2>/dev/null || true

echo "===== 10. AOSP integration bundle ====="
./tools/export-aosp-bundle.sh "$WORK/aosp-bundle"
tar -czf "$OUT/DuchampEssential-AOSP-bundle.tar.gz" -C "$WORK/aosp-bundle" .

echo
echo "===== DONE ====="
ls -la "$OUT/"
