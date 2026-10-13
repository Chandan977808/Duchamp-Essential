#!/system/bin/sh

ui_print "***************************************"
ui_print "           Duchamp Essential"
ui_print "      KernelSU Next / Magisk"
ui_print "***************************************"

if [ "${KSU:-false}" = "true" ]; then
    DUCHAMP_MANAGER="KernelSU Next"
    DUCHAMP_MANAGER_VERSION="${KSU_VER:-unknown}"
elif [ -n "${MAGISK_VER_CODE:-}" ]; then
    DUCHAMP_MANAGER="Magisk"
    DUCHAMP_MANAGER_VERSION="${MAGISK_VER:-unknown}"
else
    abort "! Install from KernelSU Next Manager or the Magisk app"
fi

if [ "$BOOTMODE" != "true" ]; then
    abort "! Install from the root manager while Android is running"
fi

if [ "$ARCH" != "arm64" ]; then
    abort "! Duchamp Essential requires an arm64 device"
fi

DUCHAMP_PRODUCT="$(getprop ro.product.device)"
DUCHAMP_VENDOR="$(getprop ro.product.vendor.device)"
case "$DUCHAMP_PRODUCT $DUCHAMP_VENDOR" in
    *duchamp*) ;;
    *) abort "! Unsupported device: $DUCHAMP_PRODUCT / $DUCHAMP_VENDOR" ;;
esac

[ -f "$MODPATH/bin/duchamp_daemon" ] || abort "! Missing Duchamp daemon"
[ -f "$MODPATH/bin/duchamp_ctl" ] || abort "! Missing Duchamp control client"
[ -f "$MODPATH/app/DuchampEssential.apk" ] || abort "! Missing Duchamp Essential APK"
[ -x /system/bin/pm ] || abort "! Android package manager is unavailable"

DUCHAMP_PACKAGE=com.saan.duchamp.essential

duchamp_native_backend_present() {
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

    DUCHAMP_PACKAGE_PATHS="$(/system/bin/pm path "$DUCHAMP_PACKAGE" 2>/dev/null)"
    case "$DUCHAMP_PACKAGE_PATHS" in
        *package:/product/*|*package:/system_ext/*|*package:/system/*|\
        *package:/vendor/*|*package:/odm/*) return 0 ;;
    esac
    return 1
}

DUCHAMP_NATIVE_MODE=0
if duchamp_native_backend_present; then
    DUCHAMP_NATIVE_MODE=1
    touch "$MODPATH/rom-native-mode"
else
    rm -f "$MODPATH/rom-native-mode"
fi

# The module changes no system partition files, so KernelSU does not need a
# mounting metamodule. The APK remains an ordinary application; only the
# separate hardware daemon runs in the root manager domain.
touch "$MODPATH/skip_mount"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/app" 0 0 0755 0644
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
[ "$DUCHAMP_NATIVE_MODE" -eq 0 ] || set_perm "$MODPATH/rom-native-mode" 0 0 0644

if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ]; then
    ui_print "- Compatible ROM-native installation detected"
    ui_print "- Installing the signed application update without clearing data"
else
    ui_print "- Installing the unprivileged Android app"
fi
DUCHAMP_INSTALL_RESULT="$(/system/bin/pm install --user 0 -r "$MODPATH/app/DuchampEssential.apk" 2>&1)"
case "$DUCHAMP_INSTALL_RESULT" in
    *Success*) ;;
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
        if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ]; then
            ui_print "$DUCHAMP_INSTALL_RESULT"
            ui_print "! The ROM-native APK uses a different signing certificate"
            ui_print "! Android cannot safely update it with the public module APK"
            ui_print "! Update that ROM build with its original signing key"
            abort "! Android correctly refused a cross-signature system-app update"
        else
            ui_print "- Legacy Duchamp Essential signing certificate detected"
            ui_print "- Performing the one-time application signing migration"
            ui_print "- Hardware profiles under /data/adb remain unchanged"

            DUCHAMP_REMOVE_RESULT="$(/system/bin/pm uninstall "$DUCHAMP_PACKAGE" 2>&1)"
            case "$DUCHAMP_REMOVE_RESULT" in
                *Success*) ;;
                *)
                    ui_print "$DUCHAMP_REMOVE_RESULT"
                    abort "! Could not remove the legacy application"
                    ;;
            esac

            DUCHAMP_INSTALL_RESULT="$(/system/bin/pm install --user 0 "$MODPATH/app/DuchampEssential.apk" 2>&1)"
            case "$DUCHAMP_INSTALL_RESULT" in
                *Success*)
                    ui_print "- Signing migration completed"
                    ui_print "- Application-local preferences were reset once"
                    ;;
                *)
                    ui_print "$DUCHAMP_INSTALL_RESULT"
                    abort "! APK installation failed after signing migration"
                    ;;
            esac
        fi
        ;;
    *)
        ui_print "$DUCHAMP_INSTALL_RESULT"
        abort "! APK installation failed"
        ;;
esac

/system/bin/pm path "$DUCHAMP_PACKAGE" >/dev/null 2>&1 || \
    abort "! Android did not register Duchamp Essential"

DUCHAMP_EXPECTED_VERSION_CODE="$(sed -n 's/^versionCode=//p' "$MODPATH/module.prop" | head -n 1)"
DUCHAMP_INSTALLED_VERSION_CODE="$(/system/bin/dumpsys package "$DUCHAMP_PACKAGE" 2>/dev/null \
    | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
[ -n "$DUCHAMP_EXPECTED_VERSION_CODE" ] || abort "! Module versionCode is missing"
[ "$DUCHAMP_INSTALLED_VERSION_CODE" = "$DUCHAMP_EXPECTED_VERSION_CODE" ] || \
    abort "! App/module version mismatch: $DUCHAMP_INSTALLED_VERSION_CODE / $DUCHAMP_EXPECTED_VERSION_CODE"

ui_print "- Device: $DUCHAMP_PRODUCT"
ui_print "- Root manager: $DUCHAMP_MANAGER $DUCHAMP_MANAGER_VERSION"
if [ "$DUCHAMP_NATIVE_MODE" -eq 1 ]; then
    ui_print "- Mode: update layer over the ROM-native installation"
    ui_print "- App: signature-compatible update; existing data retained"
    ui_print "- Daemon: module service takes over after native init stops"
    ui_print "- State: shared with the ROM-native backend"
    ui_print "- Removal: restores the ROM APK and native init service"
else
    ui_print "- App: installed as a normal Android application"
    ui_print "- Daemon: isolated privileged module service"
fi
ui_print "- IPC: authenticated Unix and privileged-loopback transports"
ui_print "- System overlay: none; no KernelSU metamodule required"
ui_print "- Reboot once when you are ready to activate the daemon"
