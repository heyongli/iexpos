#!/bin/bash
# Console Output Verification Test
# ==================================
#
# Verifies that the console output (bm_puts) functionality works
# correctly for various output messages during kernel initialization.
#
# Background
# ----------
# The kernel uses a console subsystem that outputs messages to both serial port
# and framebuffer. This test verifies that the console initialization markers
# are properly output during boot.
#
# Test Method
# -----------
# 1. Boot kernel with serial output to file
# 2. Capture all console output during initialization
# 3. Check for specific console markers in the output
#
# Expected Patterns
# -----------------
# - "entry" - C kernel main function started
# - "vga init done" - VGA initialization completed
# - "Graphics init OK" - Graphics subsystem initialized
# - "gdb stub init done" - GDB stub initialization started
# - "gdb stub done" - GDB stub initialization completed
# - "Graphics test complete" - Demo ran to completion
#
# Expected Results
# ----------------
# - All 6 patterns must be found in serial output
# - Output must show "PASS: all checks passed"
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires kernel with console debug output enabled
# - Uses -serial file: for output capture
#
# Usage
# -----
#     ./tests/console.sh              # Build and run test
#     ./tests/console.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if all patterns found
# - Returns 1 if any pattern missing
set -e

DIR=$(pwd)
DISK=$DIR/build/vm-raw.img
TMP_OUT=/tmp/vm-console.txt

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

echo ""
echo "=== Booting VM (console test) ==="
timeout 12 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT -monitor none 2>/dev/null || true

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
check "Entry message"           "entry"
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