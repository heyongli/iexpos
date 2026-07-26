#!/bin/bash
# Test: RTC time read
# Verifies RTC can read time by checking for timestamp output
set -e

DIR=~/iexpos
DISK=$DIR/build/vm-raw.img
TMP_OUT=/tmp/vm-rtc.txt

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

echo ""
echo "=== Booting VM (RTC test) ==="
timeout 12 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT 2>/dev/null

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
