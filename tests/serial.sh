#!/bin/bash
# Serial Output Verification Test
# ================================
#
# Verifies that the serial port outputs expected boot markers
# during kernel initialization and demo execution.
#
# Background
# ----------
# The kernel uses serial port (COM1) for debug output. During boot and
# execution, it outputs specific markers that indicate successful
# initialization of various subsystems.
#
# Test Method
# -----------
# 1. Boot kernel in QEMU with serial output to console
# 2. Capture all serial output during boot and demo execution
# 3. Check for specific pattern markers in the output
#
# Expected Patterns
# -----------------
# - "PMOK" - Bootloader PM switch successful
# - "entry" - C kernel main function started
# - "Graphics init OK" - Console subsystem initialized
# - "Resolution: [0-9]*x[0-9]*x[0-9]" - VGA/VBE resolution detected
# - "Graphics test complete" - Demo ran to completion
#
# Expected Results
# ----------------
# - All 5 patterns must be found in serial output
# - Output must show "PASS: all checks passed"
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires kernel built with serial debug output enabled
# - Uses -nographic mode for serial output capture
#
# Usage
# -----
#     ./tests/serial.sh              # Build and run test
#     ./tests/serial.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if all patterns found
# - Returns 1 if any pattern missing
set -e

DIR=$(pwd)
DISK=$DIR/build/vm-raw.img
TMP_OUT=$(mktemp /tmp/vm-serial-XXXXXX.txt)

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all
fi

echo ""
echo "=== Booting VM and capturing output ==="
source $DIR/tests/kvm-check.sh
timeout 12 qemu-system-x86_64 $(get_kvm_flag) -m 2G -nographic -smp 2 -vga std -drive file=$DISK,format=raw -net none 2>&1 | tee $TMP_OUT

echo ""
echo "=== Verifying output ==="

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

check "Bootloader PM switch"     "PMOK"
check "C kernel running"         "entry"
check "Graphics init"            "Graphics init OK"
check "Resolution detected"      "Resolution: [0-9]*x[0-9]*x[0-9]"
check "Graphics test complete"   "Graphics test complete"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "=== ALL TESTS PASSED ==="
    exit 0
else
    echo "=== SOME TESTS FAILED ==="
    exit 1
fi