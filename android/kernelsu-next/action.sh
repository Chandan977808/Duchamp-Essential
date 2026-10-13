#!/system/bin/sh

MODDIR=${0%/*}
DUCHAMP_CTL="$MODDIR/bin/duchamp_ctl"

echo "Duchamp Essential"
echo ""

if [ -f "$MODDIR/rom-native-mode" ]; then
    echo "Backend mode: ROM-native update layer"
    echo "Native init service: $(getprop init.svc.duchamp_daemon 2>/dev/null)"
else
    echo "Backend mode: standalone root module"
fi

if /system/bin/pm path com.saan.duchamp.essential >/dev/null 2>&1; then
    echo "App: installed"
else
    echo "App: missing; flash the module again from your root manager"
fi

DUCHAMP_PIDS="$(pidof duchamp_daemon 2>/dev/null)"
if [ -z "$DUCHAMP_PIDS" ]; then
    echo "Daemon: waiting for activation"
    echo "Install the module and reboot when you are ready."
    exit 0
fi

DUCHAMP_PING="$($DUCHAMP_CTL PING 2>&1)"
case "$DUCHAMP_PING" in
    "OK PONG "*)
        echo "Daemon: healthy"
        echo "Daemon PID: $DUCHAMP_PIDS"
        echo "Protocol: ${DUCHAMP_PING#OK PONG }"
        DUCHAMP_PRIMARY_PID="${DUCHAMP_PIDS%% *}"
        DUCHAMP_DAEMON_CONTEXT="$(cat "/proc/$DUCHAMP_PRIMARY_PID/attr/current" 2>/dev/null)"
        [ -n "$DUCHAMP_DAEMON_CONTEXT" ] && echo "Daemon SELinux: $DUCHAMP_DAEMON_CONTEXT"
        ;;
    *)
        echo "Daemon: running but did not answer"
        echo "$DUCHAMP_PING"
        exit 1
        ;;
esac

DUCHAMP_SNAPSHOT="$($DUCHAMP_CTL GET snapshot 2>/dev/null)"
DUCHAMP_APP_CLIENT_SEEN="$(printf '%s\n' "$DUCHAMP_SNAPSHOT" | tr ';' '\n' \
    | sed -n 's/^app_client_seen=//p' | head -n 1)"
DUCHAMP_APP_CLIENT_TRANSPORT="$(printf '%s\n' "$DUCHAMP_SNAPSHOT" | tr ';' '\n' \
    | sed -n 's/^app_client_transport=//p' | head -n 1)"
if [ "$DUCHAMP_APP_CLIENT_SEEN" = "1" ]; then
    case "$DUCHAMP_APP_CLIENT_TRANSPORT" in
        3) echo "App IPC: verified (authenticated loopback)" ;;
        2) echo "App IPC: verified (daemon-initiated)" ;;
        1) echo "App IPC: verified (direct policy)" ;;
        *) echo "App IPC: verified" ;;
    esac
else
    echo "App IPC: not verified yet; open Duchamp Essential once"
fi

echo "$DUCHAMP_SNAPSHOT" | tr ';' '\n' | grep -E '^(io|touch|touch_ack|touch_resampler_ready|perf)=' 2>/dev/null
