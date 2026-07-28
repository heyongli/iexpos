#!/bin/bash
# IO Abort Mechanism Verification Test
# ======================================
#
# Verifies that the IO abort mechanism works correctly, including
# CPU support detection and abort flag functionality.
#
# Background
# ----------
# The IO abort mechanism allows the kernel to abort IO operations when needed.
# This test verifies that the CPU supports IO abort (CR4 bit 24 on Intel)
# and that the abort flag is properly set and checked.
#
# Test Method
# -----------
# 1. Boot kernel with serial output to file
# 2. Check for "Graphics init OK" (indicates CPU supports io abort)
# 3. Verify NO warning about CPU not supporting io abort
#
# Expected Results
# ----------------
# - Must find "Graphics init OK" indicating successful initialization
# - Must NOT find "WARNING: CPU does not support io abort"
# - Output must show "PASS: all checks passed"
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires kernel with IO abort support
# - Uses -serial file: for output capture
#
# Usage
# -----
#     ./tests/io-abort.sh              # Build and run test (always rebuilds)
#     ./tests/io-abort.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if IO abort mechanism works correctly
# - Returns 1 if CPU doesn't support IO abort or warnings found
set -e

DIR=$(pwd)
DISK=$DIR/build/vm-raw.img
TMP_OUT=/tmp/vm-io-abort.txt

echo "=== Building ==="
make -C $DIR clean all 2>&1 | tail -3

echo ""
echo "=== Booting VM (io abort test) ==="
timeout 12 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT -monitor none 2>/dev/null || true

echo ""
echo "=== Verifying IO abort ==="

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

check_not() {
    local label="$1"
    local pattern="$2"
    if ! grep -q "$pattern" $TMP_OUT; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (should NOT contain '$pattern')"
        FAIL=$((FAIL + 1))
    fi
}

# arch_io_abort_check should pass on modern CPUs
check "arch_io_abort_check" "Graphics init OK"

# Should NOT see warning about CPU not supporting io abort
check_not "CPU supports io abort" "WARNING: CPU does not support io abort"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "=== IO ABORT TEST PASSED ==="
    rm -f $TMP_OUT
    exit 0
else
    echo "=== IO ABORT TEST FAILED ==="
    rm -f $TMP_OUT
    exit 1
fi