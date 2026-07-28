#!/bin/bash
# Visual Output Verification Test
# =================================
#
# Verifies that the framebuffer contains visible pixels (not all-black)
# after boot, confirming that the graphics subsystem is producing output.
#
# Background
# ----------
# The kernel initializes VGA/VBE graphics and runs a demo that should produce
# visible output on the framebuffer. This test captures a screendump and verifies
# that the framebuffer is not all-zero (black).
#
# Test Method
# -----------
# 1. Boot kernel with serial output and HMP monitor
# 2. Wait for "Graphics test complete" on serial
# 3. Capture screendump via QEMU HMP monitor
# 4. Parse PPM image file and check for non-zero pixels
# 5. Use check_screendump.py for detailed pixel analysis
#
# Expected Results
# ----------------
# - Screendump file must be created
# - PPM file must have valid header (P6 format)
# - Framebuffer must contain visible content (non-zero pixel values)
# - Output must show "PASS: all pixel checks passed"
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires HMP monitor for screendump
# - Requires check_screendump.py utility
# - Uses -serial file: for output capture
#
# Usage
# -----
#     ./tests/visual.sh              # Build and run test
#     ./tests/visual.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if framebuffer contains visible content
# - Returns 1 if screendump fails or framebuffer is all-black
set -e

DIR=$(pwd)
DISK=$DIR/build/vm-raw.img
SER=$(mktemp /tmp/vm-serial-XXXXXX)
SCR=$(mktemp /tmp/vm-screendump-XXXXXX.ppm)
MON_PORT=4444

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

echo ""
echo "=== Booting VM (visual test) ==="
source $DIR/tests/kvm-check.sh

# Launch QEMU with HMP monitor on TCP
timeout 16 qemu-system-x86_64 $(get_kvm_flag) -m 2G -nographic -smp 2 -vga std \
  -drive file=$DISK,format=raw -net none \
  -monitor tcp:127.0.0.1:$MON_PORT,server,nowait \
  -serial file:$SER &

QEMU_PID=$!

echo "  Waiting for boot to finish..."
if timeout 10 bash -c "
  while ! grep -q 'Graphics test complete' $SER 2>/dev/null; do
    sleep 0.2
  done
"; then
  echo "  Serial output OK"
else
  echo "  FAIL: timed out waiting for serial output"
  kill $QEMU_PID 2>/dev/null || true; rm -f $SER; exit 1
fi

# Give the monitor time to be ready
sleep 0.5

# Send screendump via monitor
echo "  Taking screendump..."
echo "screendump $SCR" | nc -w 2 127.0.0.1 $MON_PORT 2>/dev/null || true
sleep 0.3

kill $QEMU_PID 2>/dev/null || true
wait $QEMU_PID 2>/dev/null || true

# Verify screendump
if [ ! -f "$SCR" ]; then
  echo "  FAIL: no screendump produced"
  rm -f $SER; exit 1
fi

echo "  Screendump: $(wc -c < $SCR) bytes"

# Check screendump with the pixel-analysis test script
echo "  Checking screendump..."
if python3 $DIR/tests/check_screendump.py "$SCR"; then
  echo "  PASS: all pixel checks passed"
  rm -f $SER
  echo ""
  echo "=== VISUAL TEST PASSED ==="
else
  echo "  FAIL: screendump pixel checks failed"
  rm -f $SER; exit 1
fi