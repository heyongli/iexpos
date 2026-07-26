#!/bin/bash
# Test: Console output functionality
# Verifies bm_puts works for various outputs
set -e

DIR=~/iexpos
DISK=$DIR/build/vm-raw.img
TMP_OUT=/tmp/vm-console.txt

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

echo ""
echo "=== Booting VM (console test) ==="
timeout 12 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT 2>/dev/null

echo ""
echo "=== Verifying console output ==="

PASS=0
FAIL=0

check() {
    local label="$1"
    local pattern="$2"
    if grep -q "$pattern" $TMP_OUT; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected '$pattern')"
        FAIL=$((FAIL + 1))
    fi
}

# Console markers from setup.c
check "Entry message"           "^entry$"
check "VGA init done"           "vga init done"
check "Graphics init OK"        "Graphics init OK"
check "GDB stub init"           "gdb stub init done"
check "GDB stub done"           "gdb stub done"
check "Graphics test complete"  "Graphics test complete"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "=== CONSOLE TEST PASSED ==="
    rm -f $TMP_OUT
    exit 0
else
    echo "=== CONSOLE TEST FAILED ==="
    rm -f $TMP_OUT
    exit 1
fi
