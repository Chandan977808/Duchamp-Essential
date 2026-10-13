#!/usr/bin/env bash
set -euo pipefail

DUCHAMP_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage:
  tools/integrate-aosp-rom.sh <aosp-root>
  tools/integrate-aosp-rom.sh <aosp-root> <product-makefile> <boardconfig>

Builds and verifies Duchamp Essential, then stages a self-contained integration
at vendor/duchamp-essential in an existing AOSP ROM source tree.

With the optional device-tree file arguments, the script also adds both exact
include lines idempotently. Paths may be absolute or relative to <aosp-root>.
With only <aosp-root>, it stages the bundle and prints the two lines.
EOF
}

if [ "$#" -ne 1 ] && [ "$#" -ne 3 ]; then
    usage >&2
    exit 2
fi

DUCHAMP_AOSP_ROOT="$(readlink -f "$1")"
DUCHAMP_DESTINATION="$DUCHAMP_AOSP_ROOT/vendor/duchamp-essential"

[ -f "$DUCHAMP_AOSP_ROOT/build/make/core/envsetup.mk" ] || {
    echo "Not an AOSP source root: $DUCHAMP_AOSP_ROOT" >&2
    exit 1
}

if [ -e "$DUCHAMP_DESTINATION" ]; then
    echo "Destination already exists: $DUCHAMP_DESTINATION" >&2
    echo "Remove or archive it explicitly before staging a replacement." >&2
    exit 1
fi

DUCHAMP_PRODUCT_INCLUDE='$(call inherit-product, vendor/duchamp-essential/duchamp-essential.mk)'
DUCHAMP_BOARD_INCLUDE='include vendor/duchamp-essential/BoardConfigDuchampEssential.mk'
DUCHAMP_WIRED=0

resolve_tree_file() {
    local DUCHAMP_REQUESTED="$1"
    local DUCHAMP_RESOLVED
    case "$DUCHAMP_REQUESTED" in
        /*) DUCHAMP_RESOLVED="$(readlink -f "$DUCHAMP_REQUESTED")" ;;
        *) DUCHAMP_RESOLVED="$(readlink -f "$DUCHAMP_AOSP_ROOT/$DUCHAMP_REQUESTED")" ;;
    esac
    case "$DUCHAMP_RESOLVED" in
        "$DUCHAMP_AOSP_ROOT"/*) ;;
        *)
            echo "Device-tree file is outside the AOSP root: $DUCHAMP_REQUESTED" >&2
            exit 1
            ;;
    esac
    [ -f "$DUCHAMP_RESOLVED" ] || {
        echo "Device-tree file does not exist: $DUCHAMP_RESOLVED" >&2
        exit 1
    }
    printf '%s\n' "$DUCHAMP_RESOLVED"
}

append_include_once() {
    local DUCHAMP_FILE="$1"
    local DUCHAMP_LINE="$2"
    if grep -Fxq "$DUCHAMP_LINE" "$DUCHAMP_FILE"; then
        return 0
    fi
    printf '\n# Duchamp Essential\n%s\n' "$DUCHAMP_LINE" >>"$DUCHAMP_FILE"
}

if [ "$#" -eq 3 ]; then
    DUCHAMP_PRODUCT_FILE="$(resolve_tree_file "$2")"
    DUCHAMP_BOARD_FILE="$(resolve_tree_file "$3")"
    for DUCHAMP_DEVICE_TREE_FILE in "$DUCHAMP_PRODUCT_FILE" "$DUCHAMP_BOARD_FILE"; do
        [ -w "$DUCHAMP_DEVICE_TREE_FILE" ] || {
            echo "Device-tree file is not writable: $DUCHAMP_DEVICE_TREE_FILE" >&2
            exit 1
        }
    done
fi

"$DUCHAMP_PROJECT_ROOT/tools/export-aosp-bundle.sh" "$DUCHAMP_DESTINATION"

if [ "$#" -eq 3 ]; then
    append_include_once "$DUCHAMP_PRODUCT_FILE" "$DUCHAMP_PRODUCT_INCLUDE"
    append_include_once "$DUCHAMP_BOARD_FILE" "$DUCHAMP_BOARD_INCLUDE"
    DUCHAMP_WIRED=1
fi

cat <<EOF

AOSP_INTEGRATION=PASS
STAGED_AT=$DUCHAMP_DESTINATION
DEVICE_TREE_WIRED=$DUCHAMP_WIRED
EOF

if [ "$DUCHAMP_WIRED" -eq 0 ]; then
    cat <<EOF
Add this line to the Duchamp product makefile:

  $DUCHAMP_PRODUCT_INCLUDE

Add this line to device/xiaomi/duchamp/BoardConfig.mk:

  $DUCHAMP_BOARD_INCLUDE
EOF
fi

cat <<EOF
Before building, review the native touch platform exception:

  python3 vendor/duchamp-essential/tools/prepare-aosp-touch-policy.py "$DUCHAMP_AOSP_ROOT"

This is a preview, not an automatic policy modification. Follow the staged
docs/ROM_INTEGRATION.md and apply only after maintainer review.
Then run the normal ROM build. For a focused validation first:

  m DuchampEssential duchamp_daemon duchamp_ctl selinux_policy
EOF
