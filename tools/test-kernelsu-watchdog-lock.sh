#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_SERVICE_SOURCE="$DUCHAMP_PROJECT_ROOT/android/kernelsu-next/service.sh"
DUCHAMP_TEST_ROOT="$(mktemp -d)"
DUCHAMP_TEST_RUNNER=""

duchamp_test_cleanup() {
    if [ -n "$DUCHAMP_TEST_RUNNER" ]; then
        kill "$DUCHAMP_TEST_RUNNER" 2>/dev/null || true
        wait "$DUCHAMP_TEST_RUNNER" 2>/dev/null || true
    fi
    rm -rf -- "$DUCHAMP_TEST_ROOT"
}
trap duchamp_test_cleanup EXIT

DUCHAMP_TEST_MODULE="$DUCHAMP_TEST_ROOT/saan_duchamp_essential"
DUCHAMP_TEST_STATE="$DUCHAMP_TEST_ROOT/state"
DUCHAMP_TEST_BOOT_ID="$DUCHAMP_TEST_ROOT/boot_id"
mkdir -p "$DUCHAMP_TEST_MODULE" "$DUCHAMP_TEST_STATE/watchdog.lock"

sed \
    -e "s|DUCHAMP_ROOT=/data/adb/duchamp-essential|DUCHAMP_ROOT=$DUCHAMP_TEST_STATE|" \
    -e "s|/proc/sys/kernel/random/boot_id|$DUCHAMP_TEST_BOOT_ID|" \
    "$DUCHAMP_SERVICE_SOURCE" >"$DUCHAMP_TEST_MODULE/service.sh"
chmod 0755 "$DUCHAMP_TEST_MODULE/service.sh"
printf '%s\n' 'current-test-boot' >"$DUCHAMP_TEST_BOOT_ID"

# Reproduce the field failure: a stale lock from the previous boot contains
# the same numeric PID assigned to the newly launched service process.
(
    printf '%s\n' "$BASHPID" >"$DUCHAMP_TEST_STATE/watchdog.lock/pid"
    printf '%s\n' 'previous-test-boot' >"$DUCHAMP_TEST_STATE/watchdog.lock/boot_id"
    exec bash "$DUCHAMP_TEST_MODULE/service.sh"
) &
DUCHAMP_TEST_RUNNER=$!

DUCHAMP_TEST_ATTEMPT=0
while [ "$DUCHAMP_TEST_ATTEMPT" -lt 50 ]; do
    DUCHAMP_TEST_ATTEMPT=$((DUCHAMP_TEST_ATTEMPT + 1))
    DUCHAMP_LOCK_PID="$(cat "$DUCHAMP_TEST_STATE/watchdog.lock/pid" 2>/dev/null || true)"
    DUCHAMP_LOCK_BOOT_ID="$(cat "$DUCHAMP_TEST_STATE/watchdog.lock/boot_id" 2>/dev/null || true)"
    if [ "$DUCHAMP_LOCK_PID" = "$DUCHAMP_TEST_RUNNER" ] \
        && [ "$DUCHAMP_LOCK_BOOT_ID" = 'current-test-boot' ]; then
        echo "WATCHDOG_PID_REUSE_TEST=PASS"
        exit 0
    fi
    sleep 0.02
done

echo "Watchdog did not reclaim a same-PID lock from the previous boot" >&2
exit 1
