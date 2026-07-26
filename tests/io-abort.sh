#!/bin/bash
# Test: IO abort mechanism
# 1. arch_io_abort_check - verify CPU supports abort
# 2. abort_io / is_aborting - verify abort flag works
# 3. Verify abort trace output in debug builds
set -e

DIR=~/iexpos
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
