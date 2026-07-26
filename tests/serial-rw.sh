#!/bin/bash
# Test: serial port loopback read/write via serial_rw_test()
# Kernel writes 4 known bytes to THR in loopback, reads back from RBR,
# compares, outputs SRW:P/F. Script greps for SRW:P.
set -e

DIR=~/iexpos
DISK=$DIR/build/vm-raw.img
TMP_OUT=/tmp/vm-serial-rw.txt

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all
fi

echo ""
echo "=== Booting VM and capturing output ==="
timeout 12 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT -monitor none 2>/dev/null || true

echo ""
echo "=== Verifying serial read/write ==="

if grep -q "SRW:P" $TMP_OUT; then
    echo "  PASS: Serial read/write"
    exit 0
else
    echo "  FAIL: Serial read/write (expected 'SRW:P')"
    grep "SRW" $TMP_OUT || echo "  (no SRW line found)"
    exit 1
fi
