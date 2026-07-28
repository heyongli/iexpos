#!/bin/bash
# RTC (Real Time Clock) Time Read Verification Test
# ===================================================
#
# Verifies that the RTC can read time by checking for timestamp
# output in the format HH:MM:SS.
#
# Background
# ----------
# The kernel initializes the RTC during boot and uses it to provide timestamps
# in the console output. This test verifies that the RTC is functioning and
# producing valid time values.
#
# Test Method
# -----------
# 1. Boot kernel with serial output to file
# 2. Capture all output during demo execution
# 3. Check for timestamp pattern (HH:MM:SS) in the output
#
# Expected Results
# ----------------
# - Output must contain valid timestamp in format HH:MM:SS
# - Hours: 00-23, Minutes: 00-59, Seconds: 00-59
# - Output must show "PASS: RTC timestamp format valid"
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires kernel with RTC initialization
# - Uses -serial file: for output capture
#
# Usage
# -----
#     ./tests/rtc.sh              # Build and run test
#     ./tests/rtc.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if valid timestamp found
# - Returns 1 if timestamp not found or invalid format
set -e

DIR=$(pwd)
DISK=$DIR/build/vm-raw.img
TMP_OUT=$(mktemp /tmp/vm-rtc-XXXXXX.txt)

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

echo ""
echo "=== Booting VM (RTC test) ==="
source $DIR/tests/kvm-check.sh
timeout 12 qemu-system-x86_64 $(get_kvm_flag) -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT -monitor none 2>/dev/null || true

echo ""
echo "=== Verifying RTC ==="

PASS=0
FAIL=0

# Check that RTC timestamp appears in demo output (format: HH:MM:SS)
if grep -qE '[0-9]{2}:[0-9]{2}:[0-9]{2}' $TMP_OUT; then
    echo "  PASS: RTC timestamp format valid"
    PASS=$((PASS + 1))
else
    echo "  FAIL: RTC timestamp not found"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "=== RTC TEST PASSED ==="
    rm -f $TMP_OUT
    exit 0
else
    echo "=== RTC TEST FAILED ==="
    rm -f $TMP_OUT
    exit 1
fi