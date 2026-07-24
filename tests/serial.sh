#!/bin/bash
# Test: serial output contains expected boot markers
# Checks: PMOK (PM switch), entry (kernel_main), Graphics init OK (console),
#         Graphics test complete (full demo ran to end)
set -e

DIR=~/iexpos
DISK=$DIR/vm-raw.img
TMP_OUT=/tmp/vm-test-output.txt

echo "=== Building ==="
make -C $DIR clean all

echo ""
echo "=== Booting VM and capturing output ==="
sg kvm -c "timeout 10 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -hda $DISK -net none" 2>&1 | tee $TMP_OUT

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
