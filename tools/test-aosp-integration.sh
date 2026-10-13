#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DUCHAMP_AOSP="$DUCHAMP_PROJECT_ROOT/android/aosp"
DUCHAMP_PRODUCT_PRIVATE="$DUCHAMP_AOSP/sepolicy/product/private"
DUCHAMP_VENDOR_POLICY="$DUCHAMP_AOSP/sepolicy/vendor/duchamp_daemon.te"
DUCHAMP_GENFS="$DUCHAMP_AOSP/sepolicy/vendor/genfs_contexts"

for DUCHAMP_REQUIRED in \
    Android.bp BoardConfigDuchampEssential.mk duchamp-essential.mk duchamp_daemon.rc \
    sepolicy/product/public/duchamp_daemon.te \
    sepolicy/product/private/file_contexts \
    sepolicy/product/private/keys.conf \
    sepolicy/product/private/mac_permissions.xml \
    sepolicy/product/private/duchamp_app.te \
    sepolicy/product/private/duchamp_daemon.te \
    sepolicy/product/private/seapp_contexts \
    sepolicy/vendor/genfs_contexts \
    sepolicy/vendor/duchamp_daemon.te; do
    [ -s "$DUCHAMP_AOSP/$DUCHAMP_REQUIRED" ] || {
        echo "Missing AOSP integration file: $DUCHAMP_REQUIRED" >&2
        exit 1
    }
done

grep -Fq 'presigned: true' "$DUCHAMP_AOSP/Android.bp"
grep -Fq 'preprocessed: true' "$DUCHAMP_AOSP/Android.bp"
grep -Fq 'dex_preopt:' "$DUCHAMP_AOSP/Android.bp"
grep -Fq '"libbinder_ndk"' "$DUCHAMP_AOSP/Android.bp"
if grep -Eq 'certificate:[[:space:]]*"platform"|check_elf_files:[[:space:]]*false' \
    "$DUCHAMP_AOSP/Android.bp"; then
    echo "AOSP prebuilts must retain their signing identity and ELF checks" >&2
    exit 1
fi

grep -Fq 'PRODUCT_PACKAGES_DEBUG +=' "$DUCHAMP_AOSP/duchamp-essential.mk"
if sed -n '/^PRODUCT_PACKAGES +=/,/^$/p' "$DUCHAMP_AOSP/duchamp-essential.mk" \
    | grep -Fq 'duchamp_ctl'; then
    echo "duchamp_ctl must not be installed in production user builds" >&2
    exit 1
fi

grep -Fxq '[@DUCHAMP_ESSENTIAL]' "$DUCHAMP_PRODUCT_PRIVATE/keys.conf"
grep -Fq 'vendor/duchamp-essential/prebuilt/DuchampEssential.x509.pem' \
    "$DUCHAMP_PRODUCT_PRIVATE/keys.conf"
grep -Fq '<signer signature="@DUCHAMP_ESSENTIAL">' \
    "$DUCHAMP_PRODUCT_PRIVATE/mac_permissions.xml"
grep -Fq '<package name="com.saan.duchamp.essential">' \
    "$DUCHAMP_PRODUCT_PRIVATE/mac_permissions.xml"
grep -Fq '<seinfo value="duchamp_essential"' \
    "$DUCHAMP_PRODUCT_PRIVATE/mac_permissions.xml"
python3 - "$DUCHAMP_PRODUCT_PRIVATE/mac_permissions.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
if root.tag != "policy":
    raise SystemExit("mac_permissions.xml root must be <policy>")
PY

grep -Fxq \
    'user=_app seinfo=duchamp_essential name=com.saan.duchamp.essential domain=duchamp_app type=app_data_file levelFrom=all' \
    "$DUCHAMP_PRODUCT_PRIVATE/seapp_contexts"
grep -Fq 'untrusted_app_domain(duchamp_app)' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_app.te"
grep -Fq 'net_domain(duchamp_app)' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_app.te"
grep -Fq 'typeattribute duchamp_app coredomain;' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_app.te"
grep -Fq 'allow duchamp_app duchamp_daemon:unix_stream_socket connectto;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'typeattribute duchamp_daemon mlstrustedsubject;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'settings_service:service_manager find;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'window_service:service_manager find;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'activity_service:service_manager find;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'overlay_service:service_manager find;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'allow system_server duchamp_daemon:fd use;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'allow system_server duchamp_daemon:fifo_file write;' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'toolbox_exec:file' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'execute_no_trans' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
if grep -Fq 'shell_exec:file' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"; then
    echo "AOSP daemon must call cmd directly instead of executing shell wrappers" >&2
    exit 1
fi
if grep -Eq 'allow[[:space:]]+(appdomain|untrusted_app)[[:space:]]+duchamp_daemon' \
    "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"; then
    echo "AOSP socket access must remain restricted to duchamp_app" >&2
    exit 1
fi

if grep -Eq '(^|[[:space:]])permissive[[:space:]]+duchamp_daemon|allow[[:space:]]+duchamp_daemon[[:space:]]+sysfs:file|ctl_(start|stop)_prop' \
    "$DUCHAMP_AOSP"/sepolicy/{product/private,product/public,vendor}/*; then
    echo "AOSP policy contains an unsafe or obsolete grant" >&2
    exit 1
fi

# Traversal is required on the reported vendor base; broader parent access is not.
grep -Fxq 'allow duchamp_daemon sysfs_batteryinfo:dir search;' "$DUCHAMP_VENDOR_POLICY"
if grep '^[[:space:]]*allow .*sysfs_batteryinfo' "$DUCHAMP_VENDOR_POLICY" \
    | grep -Fvx 'allow duchamp_daemon sysfs_batteryinfo:dir search;'; then
    echo "Battery parent access must remain directory-search only" >&2
    exit 1
fi
grep -Fxq 'allow duchamp_daemon sysfs_battery_supply:dir search;' "$DUCHAMP_VENDOR_POLICY"
grep -Fxq 'allow duchamp_daemon sysfs_usb_supply:dir search;' "$DUCHAMP_VENDOR_POLICY"

# Installed-app discovery now needs lookup, not package mutation privileges.
grep -Fxq 'allow duchamp_daemon package_service:service_manager find;' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fxq 'read_logd(duchamp_daemon)' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
if grep 'package_service' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te" | grep -Fvx 'allow duchamp_daemon package_service:service_manager find;'; then
    echo "Package discovery must use only the scoped service lookup grant" >&2
    exit 1
fi

grep -Fq 'type sysfs_duchamp_mali_devfreq, fs_type, sysfs_type;' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'type sysfs_duchamp_touch, fs_type, sysfs_type;' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'allow duchamp_daemon sysfs_battery_supply:file rw_file_perms;' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'netlink_kobject_uevent_socket' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq 'allow duchamp_daemon vendor_sysfs_displayfeature:file r_file_perms;' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'allow duchamp_daemon input_device:chr_file rw_file_perms;' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'binder_call(duchamp_daemon, hal_touchfeature_xiaomi_default)' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'binder_call(duchamp_daemon, vendor_hal_displayfeature_xiaomi_default)' \
    "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'allow duchamp_daemon hal_touchfeature_xiaomi_service:service_manager find;' \
    "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'allow duchamp_daemon hal_touchfeature_xiaomi_default:process ptrace;' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'allow duchamp_daemon hal_touchfeature_xiaomi_default:dir search;' "$DUCHAMP_VENDOR_POLICY"
grep -Fq 'typeattribute duchamp_daemon duchamp_native_touch_access;' "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"
grep -Fq '/devices/platform/soc/13000000.mali/devfreq/13000000.mali' "$DUCHAMP_GENFS"
grep -Fq '/devices/platform/goodix_ts.0' "$DUCHAMP_GENFS"

grep -Fq 'user root' "$DUCHAMP_AOSP/duchamp_daemon.rc"
grep -Fq 'setenv DUCHAMP_STATE_DIR /data/system/duchamp-essential' "$DUCHAMP_AOSP/duchamp_daemon.rc"
grep -Fq 'setenv DUCHAMP_TOUCH_DIRECT_INPUT 1' "$DUCHAMP_AOSP/duchamp_daemon.rc"
grep -Eq '^[[:space:]]*group.*input' "$DUCHAMP_AOSP/duchamp_daemon.rc"
grep -Fq 'capabilities DAC_OVERRIDE SYS_ADMIN SYS_NICE SYS_PTRACE' \
    "$DUCHAMP_AOSP/duchamp_daemon.rc"
if grep -Eq 'DAC_READ_SEARCH|readproc' \
    "$DUCHAMP_AOSP/duchamp_daemon.rc" "$DUCHAMP_PRODUCT_PRIVATE/duchamp_daemon.te"; then
    echo "AOSP daemon requests an unreviewed capability or process group" >&2
    exit 1
fi
grep -Fq 'mod touch_resampler;' "$DUCHAMP_PROJECT_ROOT/runtime/daemon-rust/src/lib.rs"
grep -Fq 'DUCHAMP_TOUCH_DIRECT_INPUT' \
    "$DUCHAMP_PROJECT_ROOT/runtime/daemon-rust/src/touch_resampler.rs"
grep -Fq 'on property:sys.boot_completed=1' "$DUCHAMP_AOSP/duchamp_daemon.rc"

DUCHAMP_PLAT_CIL="${DUCHAMP_PLAT_SEPOLICY_CIL:-}"
if [ -n "$DUCHAMP_PLAT_CIL" ]; then
    [ -f "$DUCHAMP_PLAT_CIL" ] || {
        echo "DUCHAMP_PLAT_SEPOLICY_CIL does not exist: $DUCHAMP_PLAT_CIL" >&2
        exit 1
    }
    command -v secilc >/dev/null 2>&1 || {
        echo "secilc is required for the requested platform neverallow check" >&2
        exit 1
    }
    DUCHAMP_CONTRACT_CIL="$DUCHAMP_PROJECT_ROOT/tools/aosp-policy-contract.cil"
    DUCHAMP_POLICY_TMP="$(mktemp -d)"
    trap 'rm -rf "$DUCHAMP_POLICY_TMP"' EXIT

    # An incomplete or failing baseline is not a successful policy check.
    # Never disable neverallows or excuse unknown diagnostics as OEM noise.
    secilc -m -M true -G -c 30 "$DUCHAMP_PLAT_CIL" \
        -o "$DUCHAMP_POLICY_TMP/baseline-policy" -f /dev/null
    secilc -m -M true -G -c 30 \
        "$DUCHAMP_PLAT_CIL" "$DUCHAMP_CONTRACT_CIL" \
        -o "$DUCHAMP_POLICY_TMP/combined-policy" -f /dev/null
    echo 'AOSP_PLATFORM_NEVERALLOW_TEST=PASS (synthetic probe only)'
else
    echo 'AOSP_PLATFORM_NEVERALLOW_TEST=SKIP (set DUCHAMP_PLAT_SEPOLICY_CIL)'
fi

echo 'AOSP_INTEGRATION_CONTRACT_TEST=PASS'
