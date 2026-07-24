#!/bin/bash
set -e

DIR=/home/radio/iexpos
DISK=$DIR/vm-raw.img
SER=/tmp/qemu-vm-serial
SCR=/tmp/qemu-vm-screendump.ppm
MON_PORT=4444

echo "=== Building ==="
make -C $DIR clean all 2>&1 | tail -3

echo ""
echo "=== Booting VM (visual test) ==="

# Launch QEMU with HMP monitor on TCP
timeout 12 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std \
  -hda $DISK -net none \
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

# Check the PPM has non-background pixels
# Skip PPM header (3 lines), sample bytes at offset 100
SAMPLE=$(dd if="$SCR" bs=1 skip=100 count=200 2>/dev/null | od -An -tu1 | awk '{for(i=1;i<=NF;i++) s+=$1} END {print s}')
if [ -z "$SAMPLE" ] || [ "$SAMPLE" -eq 0 ]; then
  echo "  FAIL: framebuffer appears all black (sample=$SAMPLE)"
  rm -f $SER; exit 1
fi

echo "  PASS: framebuffer has visible content (pixel sum = $SAMPLE)"
rm -f $SER
echo ""
echo "=== VISUAL TEST PASSED ==="
