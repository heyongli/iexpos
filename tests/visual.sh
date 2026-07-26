#!/bin/bash
# Test: framebuffer contains visible pixels (not all-black) after boot
# Captures QEMU screendump via HMP monitor, samples non-zero pixel values.
# QEMU -serial file: → wait "Graphics test complete" → screendump via monitor
# → parse PPM sample bytes → non-zero sum = framebuffer has content.
set -e

DIR=/home/radio/iexpos
DISK=$DIR/build/vm-raw.img
SER=/tmp/qemu-vm-serial
SCR=/tmp/qemu-vm-screendump.ppm
MON_PORT=4444

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

echo ""
echo "=== Booting VM (visual test) ==="

# Launch QEMU with HMP monitor on TCP
timeout 16 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std \
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
