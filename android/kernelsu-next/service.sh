#!/system/bin/sh

MODDIR=${0%/*}
DUCHAMP_ROOT=/data/adb/duchamp-essential
DUCHAMP_NATIVE_STATE_ROOT=/data/system/duchamp-essential
DUCHAMP_DAEMON="$MODDIR/bin/duchamp_daemon"
DUCHAMP_LOG="$DUCHAMP_ROOT/backend.log"
DUCHAMP_LOG_OLD="$DUCHAMP_ROOT/backend.log.1"
DUCHAMP_WATCHDOG_PID="$DUCHAMP_ROOT/watchdog.pid"
DUCHAMP_WATCHDOG_LOCK="$DUCHAMP_ROOT/watchdog.lock"
DUCHAMP_WATCHDOG_BOOT_ID="$DUCHAMP_WATCHDOG_LOCK/boot_id"
DUCHAMP_SERVICE_PATH="$MODDIR/service.sh"
DUCHAMP_CURRENT_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
DUCHAMP_PACKAGE=com.saan.duchamp.essential

export DUCHAMP_REVERSE_IPC=1
export DUCHAMP_LOOPBACK_IPC=1

duchamp_native_backend_present() {
    [ -f "$MODDIR/rom-native-mode" ] && return 0

    for DUCHAMP_NATIVE_BINARY in \
        /product/bin/duchamp_daemon \
        /system_ext/bin/duchamp_daemon \
        /system/bin/duchamp_daemon \
        /vendor/bin/duchamp_daemon \
        /odm/bin/duchamp_daemon; do
        [ -x "$DUCHAMP_NATIVE_BINARY" ] && return 0
    done

    for DUCHAMP_NATIVE_SERVICE in duchamp_daemon duchamp_essentiald; do
        [ -n "$(getprop "init.svc.$DUCHAMP_NATIVE_SERVICE" 2>/dev/null)" ] && return 0
    done
    return 1
}

DUCHAMP_NATIVE_MODE=0
if duchamp_native_backend_present; then
    DUCHAMP_NATIVE_MODE=1
    export DUCHAMP_STATE_DIR="$DUCHAMP_NATIVE_STATE_ROOT"
else
    export DUCHAMP_STATE_DIR="$DUCHAMP_ROOT"
fi

umask 077
mkdir -p "$DUCHAMP_ROOT"
chmod 0700 "$DUCHAMP_ROOT" 2>/dev/null
if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ]; then
    mkdir -p "$DUCHAMP_NATIVE_STATE_ROOT"
    chmod 0700 "$DUCHAMP_NATIVE_STATE_ROOT" 2>/dev/null
    /system/bin/restorecon -RF "$DUCHAMP_NATIVE_STATE_ROOT" 2>/dev/null || \
        /system/bin/restorecon -R "$DUCHAMP_NATIVE_STATE_ROOT" 2>/dev/null || true
fi

DUCHAMP_LOG_BYTES=0
if [ -f "$DUCHAMP_LOG" ]; then
    DUCHAMP_LOG_BYTES="$(wc -c <"$DUCHAMP_LOG" 2>/dev/null)"
fi
case "$DUCHAMP_LOG_BYTES" in
    ''|*[!0-9]*) ;;
    *)
        if [ "$DUCHAMP_LOG_BYTES" -gt 1048576 ]; then
            mv -f "$DUCHAMP_LOG" "$DUCHAMP_LOG_OLD"
        fi
        ;;
esac

# mkdir is an atomic early-boot lock and prevents duplicate watchdog loops.
if ! mkdir "$DUCHAMP_WATCHDOG_LOCK" 2>/dev/null; then
    DUCHAMP_EXISTING_PID="$(cat "$DUCHAMP_WATCHDOG_LOCK/pid" 2>/dev/null)"
    DUCHAMP_EXISTING_BOOT_ID="$(cat "$DUCHAMP_WATCHDOG_BOOT_ID" 2>/dev/null)"
    DUCHAMP_EXISTING_CMDLINE=""
    if [ -n "$DUCHAMP_CURRENT_BOOT_ID" ] \
        && [ "$DUCHAMP_EXISTING_BOOT_ID" = "$DUCHAMP_CURRENT_BOOT_ID" ] \
        && [ "$DUCHAMP_EXISTING_PID" != "$$" ] \
        && kill -0 "$DUCHAMP_EXISTING_PID" 2>/dev/null; then
        DUCHAMP_EXISTING_CMDLINE="$(tr '\000' ' ' <"/proc/$DUCHAMP_EXISTING_PID/cmdline" 2>/dev/null)"
    fi
    case "$DUCHAMP_EXISTING_CMDLINE" in
        *"$DUCHAMP_SERVICE_PATH"*) exit 0 ;;
    esac

    rm -f "$DUCHAMP_WATCHDOG_LOCK/pid" "$DUCHAMP_WATCHDOG_BOOT_ID"
    rmdir "$DUCHAMP_WATCHDOG_LOCK" 2>/dev/null || exit 0
    mkdir "$DUCHAMP_WATCHDOG_LOCK" 2>/dev/null || exit 0
fi

printf '%s\n' "$$" >"$DUCHAMP_WATCHDOG_PID"
printf '%s\n' "$$" >"$DUCHAMP_WATCHDOG_LOCK/pid"
printf '%s\n' "$DUCHAMP_CURRENT_BOOT_ID" >"$DUCHAMP_WATCHDOG_BOOT_ID"

# Remove watchdogs left by older development packages of this same module.
for DUCHAMP_PROC in /proc/[0-9]*; do
    DUCHAMP_PID="${DUCHAMP_PROC##*/}"
    [ "$DUCHAMP_PID" = "$$" ] && continue
    DUCHAMP_CMDLINE="$(tr '\000' ' ' <"$DUCHAMP_PROC/cmdline" 2>/dev/null)"
    case "$DUCHAMP_CMDLINE" in
        *"$DUCHAMP_SERVICE_PATH"*)
            kill -9 "$DUCHAMP_PID" 2>/dev/null
            ;;
    esac
done

duchamp_cleanup() {
    DUCHAMP_OWNER="$(cat "$DUCHAMP_WATCHDOG_LOCK/pid" 2>/dev/null)"
    if [ "$DUCHAMP_OWNER" = "$$" ]; then
        rm -f "$DUCHAMP_WATCHDOG_PID" "$DUCHAMP_WATCHDOG_LOCK/pid" "$DUCHAMP_WATCHDOG_BOOT_ID"
        rmdir "$DUCHAMP_WATCHDOG_LOCK" 2>/dev/null
    fi
}

trap duchamp_cleanup EXIT
trap 'exit 0' HUP INT TERM

duchamp_stop_native_services() {
    [ "$DUCHAMP_NATIVE_MODE" -eq 1 ] || return 0

    for DUCHAMP_NATIVE_SERVICE in duchamp_daemon duchamp_essentiald; do
        DUCHAMP_NATIVE_STATE="$(getprop "init.svc.$DUCHAMP_NATIVE_SERVICE" 2>/dev/null)"
        case "$DUCHAMP_NATIVE_STATE" in
            ''|stopped) ;;
            *) /system/bin/setprop ctl.stop "$DUCHAMP_NATIVE_SERVICE" 2>/dev/null || true ;;
        esac
    done

    DUCHAMP_STOP_ATTEMPT=0
    while [ "$DUCHAMP_STOP_ATTEMPT" -lt 10 ]; do
        DUCHAMP_NATIVE_RUNNING=0
        for DUCHAMP_NATIVE_SERVICE in duchamp_daemon duchamp_essentiald; do
            DUCHAMP_NATIVE_STATE="$(getprop "init.svc.$DUCHAMP_NATIVE_SERVICE" 2>/dev/null)"
            case "$DUCHAMP_NATIVE_STATE" in
                starting|running|restarting|stopping) DUCHAMP_NATIVE_RUNNING=1 ;;
            esac
        done
        [ "$DUCHAMP_NATIVE_RUNNING" -eq 1 ] || return 0
        DUCHAMP_STOP_ATTEMPT=$((DUCHAMP_STOP_ATTEMPT + 1))
        sleep 1
    done
    return 1
}

duchamp_kill_existing_daemons() {
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
}

duchamp_resolve_app_uid() {
    DUCHAMP_PACKAGE_ENTRY="$(/system/bin/pm list packages -U "$DUCHAMP_PACKAGE" 2>/dev/null \
        | sed -n "s/^package:$DUCHAMP_PACKAGE[[:space:]]*uid:\([0-9][0-9]*\).*$/\1/p" \
        | head -n 1)"
    case "$DUCHAMP_PACKAGE_ENTRY" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$DUCHAMP_PACKAGE_ENTRY" -ge 10000 ] 2>/dev/null; then
                printf '%s\n' "$DUCHAMP_PACKAGE_ENTRY"
                return 0
            fi
            ;;
    esac

    DUCHAMP_PACKAGE_ENTRY="$(/system/bin/dumpsys package "$DUCHAMP_PACKAGE" 2>/dev/null \
        | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' \
        | head -n 1)"
    case "$DUCHAMP_PACKAGE_ENTRY" in
        ''|*[!0-9]*) return 1 ;;
        *)
            [ "$DUCHAMP_PACKAGE_ENTRY" -ge 10000 ] 2>/dev/null || return 1
            printf '%s\n' "$DUCHAMP_PACKAGE_ENTRY"
            ;;
    esac
}

# KernelSU/Magisk late-start scripts may run while framework/vendor services
# are still publishing their boot defaults. Start the backend only after the
# completed Android boot so every persisted Duchamp setting wins that race.
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    sleep 1
done

if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ]; then
    echo "DUCHAMP_MODULE_MODE rom_native_update state_dir=$DUCHAMP_STATE_DIR" >>"$DUCHAMP_LOG"
    while ! duchamp_stop_native_services; do
        echo "DUCHAMP_NATIVE_TAKEOVER_WAIT init_service_still_running" >>"$DUCHAMP_LOG"
        sleep 2
    done
    echo "DUCHAMP_NATIVE_TAKEOVER_READY init_service=stopped" >>"$DUCHAMP_LOG"
else
    echo "DUCHAMP_MODULE_MODE standalone state_dir=$DUCHAMP_STATE_DIR" >>"$DUCHAMP_LOG"
fi

# Start the daemon shipped by this module, never an old module or init-owned
# binary. Native init is stopped first so it cannot restart a competing daemon.
duchamp_kill_existing_daemons

# Pin the daemon to the UID Android assigned to this exact APK. The daemon
# validates Unix peers with SO_PEERCRED and privileged-loopback peers against
# the kernel TCP table, so no app-to-root SELinux relaxation is required and no
# other ordinary application can issue hardware commands.
DUCHAMP_UID_WAIT_LOGGED=0
while true; do
    DUCHAMP_APP_UID="$(duchamp_resolve_app_uid)"
    if [ -n "$DUCHAMP_APP_UID" ]; then
        break
    fi
    if [ "$DUCHAMP_UID_WAIT_LOGGED" -eq 0 ]; then
        echo "DUCHAMP_MODULE_APP_UID_WAIT package=$DUCHAMP_PACKAGE" >>"$DUCHAMP_LOG"
        DUCHAMP_UID_WAIT_LOGGED=1
    fi
    sleep 2
done
export DUCHAMP_APP_UID
echo "DUCHAMP_MODULE_APP_UID uid=$DUCHAMP_APP_UID" >>"$DUCHAMP_LOG"

while true; do
    if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ] && ! duchamp_stop_native_services; then
        echo "DUCHAMP_NATIVE_TAKEOVER_WAIT init_service_restarted" >>"$DUCHAMP_LOG"
        sleep 2
        continue
    fi
    if [ -x "$DUCHAMP_DAEMON" ] && ! pidof duchamp_daemon >/dev/null 2>&1; then
        echo "DUCHAMP_MODULE_DAEMON_START path=$DUCHAMP_DAEMON" >>"$DUCHAMP_LOG"
        "$DUCHAMP_DAEMON" >>"$DUCHAMP_LOG" 2>&1
        DUCHAMP_EXIT=$?
        echo "DUCHAMP_MODULE_DAEMON_EXIT code=$DUCHAMP_EXIT" >>"$DUCHAMP_LOG"
    fi
    sleep 2
done
