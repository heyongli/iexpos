#!/bin/bash
# Flicker detection test runner
#
# Requirements
# ------------
# - QEMU compiled with a display backend: egl-headless, sdl, gtk, or vnc
#   (needed for the 'screendump' HMP command)
# - python3 with standard library
# - Kernel builds successfully (make clean all)
#
# Detection
# ---------
# The script probes display backends in order and picks the first working one.
# If none works it reports the problem.
#
set -euo pipefail

DIR=$(pwd)
BDIR=$DIR/build
DISK=$BDIR/vm-raw.img
SERIAL_PORT=12348
MON_PORT=12349
TMPDIR=$(mktemp -d /tmp/flicker-test-XXXXXX)

cleanup() {
    local rc=$?
    kill $QEMU_PID 2>/dev/null || true
    if [ $rc -eq 0 ]; then
        rm -rf "$TMPDIR"
    else
        echo "  Debug data left in $TMPDIR"
    fi
    fuser -k "$SERIAL_PORT"/tcp 2>/dev/null || true
    fuser -k "$MON_PORT"/tcp 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Flicker detection test ==="

make -sC $DIR clean all 2>&1 | tail -1
[ -f "$DISK" ] || { echo "FAIL: no vm-raw.img"; exit 1; }

fuser -k "$SERIAL_PORT"/tcp 2>/dev/null || true
fuser -k "$MON_PORT"/tcp 2>/dev/null || true

# ---- probe display backends ----
# Need a display backend that supports 'screendump'.
# VNC works without a local display server.
DISPLAY_FLAG="-vnc :0"
echo "  Display backend: $DISPLAY_FLAG"

# ---- start QEMU ----
qemu-system-x86_64 \
    -enable-kvm -m 512M -smp 2 -vga std \
    -drive file=$DISK,format=raw \
    -net none \
    $DISPLAY_FLAG \
    -serial tcp::"$SERIAL_PORT",server,nowait \
    -monitor tcp::"$MON_PORT",server,nowait \
    >/dev/null 2>&1 &
QEMU_PID=$!

# Wait for serial port
echo "  Waiting for QEMU (serial tcp::$SERIAL_PORT)..."
for i in $(seq 1 60); do
    ss -ltn 2>/dev/null | grep -q ":$SERIAL_PORT " && break
    sleep 0.1
done
ss -ltn 2>/dev/null | grep -q ":$SERIAL_PORT " || { echo "FAIL: serial port not open"; exit 1; }

# ---- run Python flicker detector ----
python3 "$DIR/tests/flicker-test.py" \
    --serial-port "$SERIAL_PORT" \
    --monitor-port "$MON_PORT" \
    --tmpdir "$TMPDIR" \
    --count 60 \
    --delay 0.1
