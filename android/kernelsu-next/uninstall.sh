#!/system/bin/sh

MODDIR=${0%/*}
DUCHAMP_ROOT=/data/adb/duchamp-essential
DUCHAMP_WATCHDOG_LOCK="$DUCHAMP_ROOT/watchdog.lock"
DUCHAMP_WATCHDOG_PID="$(cat "$DUCHAMP_ROOT/watchdog.pid" 2>/dev/null)"
DUCHAMP_PACKAGE=com.saan.duchamp.essential
DUCHAMP_NATIVE_MODE=0
[ -f "$MODDIR/rom-native-mode" ] && DUCHAMP_NATIVE_MODE=1

case "$DUCHAMP_WATCHDOG_PID" in
    ''|*[!0-9]*) ;;
    *) kill "$DUCHAMP_WATCHDOG_PID" 2>/dev/null ;;
esac

for DUCHAMP_PROCESS_NAME in duchamp_daemon duchamp_essentiald; do
    for DUCHAMP_PID in $(pidof "$DUCHAMP_PROCESS_NAME" 2>/dev/null); do
        kill "$DUCHAMP_PID" 2>/dev/null
    done
done
sleep 1
for DUCHAMP_PROCESS_NAME in duchamp_daemon duchamp_essentiald; do
    for DUCHAMP_PID in $(pidof "$DUCHAMP_PROCESS_NAME" 2>/dev/null); do
        kill -9 "$DUCHAMP_PID" 2>/dev/null
    done
done

rm -f "$DUCHAMP_ROOT/watchdog.pid" "$DUCHAMP_WATCHDOG_LOCK/pid" "$DUCHAMP_WATCHDOG_LOCK/boot_id"
rmdir "$DUCHAMP_WATCHDOG_LOCK" 2>/dev/null
rm -f "$DUCHAMP_ROOT/bin/duchamp_daemon" "$DUCHAMP_ROOT/bin/duchamp_ctl"
rmdir "$DUCHAMP_ROOT/bin" 2>/dev/null
rm -f "$DUCHAMP_ROOT/backend.log" "$DUCHAMP_ROOT/backend.log.1"

if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ]; then
    # The module APK is an Android package-manager update over the matching ROM
    # system app. Revert only that update, keep package data, and return daemon
    # ownership to init. The native state directory is never removed.
    /system/bin/cmd package uninstall-system-updates "$DUCHAMP_PACKAGE" \
        >"$DUCHAMP_ROOT/native-app-rollback.log" 2>&1 || true
    /system/bin/pm enable --user 0 "$DUCHAMP_PACKAGE" >/dev/null 2>&1 || true
    for DUCHAMP_NATIVE_SERVICE in duchamp_daemon duchamp_essentiald; do
        if [ -n "$(getprop "init.svc.$DUCHAMP_NATIVE_SERVICE" 2>/dev/null)" ]; then
            /system/bin/setprop ctl.start "$DUCHAMP_NATIVE_SERVICE" 2>/dev/null || true
        fi
    done
fi

# Standalone installations keep state.conf and the ordinary Android app so
# removing the root module does not erase user data. The app can be uninstalled
# normally from Android.
exit 0
