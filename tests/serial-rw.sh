#!/bin/bash
# Serial Port Loopback Read/Write Test
# ======================================
#
# Verifies that the serial port (UART) loopback functionality works
# correctly for both transmit (THR) and receive (RBR) operations.
#
# Background
# ----------
# The serial port test uses UART loopback mode (MCR bit 4) where transmitted
# data is immediately received back. This verifies that the UART hardware and
# driver are functioning correctly without requiring a second serial port.
#
# Test Method
# -----------
# 1. Boot kernel with serial output to file
# 2. Kernel writes 4 known bytes to THR in loopback mode
# 3. Kernel reads back from RBR and compares
# 4. Kernel outputs "SRW:P" (pass) or "SRW:F" (fail)
# 5. Test script greps for "SRW:P" in the output
#
# Expected Results
# ----------------
# - Output must contain "SRW:P" indicating successful loopback
# - All 4 bytes must match between write and read
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires kernel with UART loopback test enabled
# - Uses -serial file: for output capture
#
# Usage
# -----
#     ./tests/serial-rw.sh              # Build and run test
#     ./tests/serial-rw.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if loopback test passes ("SRW:P" found)
# - Returns 1 if loopback test fails or pattern not found
set -e

DIR=$(pwd)
DISK=$DIR/build/vm-raw.img
TMP_OUT=$(mktemp /tmp/vm-serial-rw-XXXXXX.txt)

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all
fi

echo ""
echo "=== Booting VM and capturing output ==="
source $DIR/tests/kvm-check.sh
timeout 12 qemu-system-x86_64 $(get_kvm_flag) -m 2G -nographic -smp 2 -vga std -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT -monitor none 2>/dev/null || true

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