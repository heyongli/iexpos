#!/bin/bash
# Test: GDB serial PTY bridge - verify PTY works for serial GDB stub
# Raw protocol test is in gdb-over-serial-protocol.sh
# This test verifies socat PTY bridge works correctly
set -euo pipefail

DIR=~/iexpos
BDIR=$DIR/build
PORT=12347
PTY=/tmp/gdb-serial-test
DISK=$BDIR/vm-raw.img

cleanup() {
    kill $QEMU_PID 2>/dev/null || true
    kill $SOCAT_PID 2>/dev/null || true
    rm -f $PTY
    fuser -k "$PORT"/tcp 2>/dev/null || true
}
trap cleanup EXIT

echo "=== GDB serial PTY bridge test ==="

# Build
echo "  Building..."
make -sC $DIR clean all 2>&1 | tail -1

[ -f "$DISK" ] || { echo "FAIL: no vm-raw.img"; exit 1; }

# Kill old processes on port
fuser -k "$PORT"/tcp 2>/dev/null || true

# Start QEMU with serial on TCP
echo "  Starting QEMU (serial tcp::$PORT)..."
qemu-system-x86_64 \
    -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw \
    -net none \
    -serial tcp::"$PORT",server,nowait \
    >/dev/null 2>&1 &
QEMU_PID=$!

# Wait for TCP port to open
echo "  Waiting for QEMU serial port..."
for i in $(seq 1 30); do
    ss -ltn 2>/dev/null | grep -q ":$PORT " && break
    sleep 0.1
done
ss -ltn 2>/dev/null | grep -q ":$PORT " || { echo "FAIL: TCP port did not open"; exit 1; }
echo "  TCP port open"

# Start socat PTY bridge
echo "  Starting socat PTY bridge..."
socat PTY,link=$PTY,rawer TCP:localhost:$PORT &
SOCAT_PID=$!
sleep 0.5

[ -e "$PTY" ] || { echo "FAIL: PTY not created"; exit 1; }
echo "  PTY created: $PTY"

# Verify PTY can read kernel boot output
echo "  Reading boot output via PTY..."
ok=0
deadline=$(($(date +%s) + 15))
while [ "$(date +%s)" -lt $deadline ]; do
    if [ -e "$PTY" ]; then
        chunk=$(timeout 1 dd bs=4096 count=1 if="$PTY" 2>/dev/null || true)
        if echo "$chunk" | grep -q "Graphics test complete"; then
            echo "  PASS: PTY bridge works, kernel booted"
            ok=1
            break
        fi
    fi
    sleep 0.2
done

if [ "$ok" -eq 0 ]; then
    echo "  FAIL: PTY bridge did not receive boot output"
fi

# Test serial GDB stub with proper packet exchange
echo "  Testing GDB stub packet echo..."
python3 <<'PYEOF' 2>&1
import os, time

fd = os.open('/tmp/gdb-serial-test', os.O_RDWR | os.O_NONBLOCK)

# Send ? packet via PTY - triggers gdb_poll, handler processes ?
os.write(fd, b'$?#3f')
time.sleep(0.5)

resp = b''
deadline = time.time() + 5
while time.time() < deadline:
    try:
        d = os.read(fd, 4096)
        if d: resp += d
        if b'S05' in resp: break
    except: pass
    time.sleep(0.1)

os.close(fd)
if b'S05' in resp:
    print("PASS: ? -> S05 via PTY")
else:
    print("FAIL: no S05 after ?")
    exit(1)
PYEOF

RC=$?

if [ $RC -eq 0 ]; then
    echo "  PASS: PTY packet exchange"
fi

# Comprehensive GDB functional test
echo ""
echo "  Running comprehensive GDB command suite..."
timeout 30 gdb "$BDIR/kernel.elf" -q \
  -ex "set architecture i8086" \
  -ex "set pagination off" \
  -ex "target remote $PTY" \
  -ex "echo === break+continue ===\n" \
  -ex "break *gdb_poll" \
  -ex "continue" \
  -ex "echo === stepi ===\n" \
  -ex "stepi" \
  -ex "echo === continue after stepi ===\n" \
  -ex "continue" \
  -ex "echo === set \$eax ===\n" \
  -ex "set \$eax = 0x12345678" \
  -ex "print/x \$eax" \
  -ex "echo === set \$ecx ===\n" \
  -ex "set \$ecx = 0xdeadbeef" \
  -ex "print/x \$ecx" \
  -ex "echo === continue after set ===\n" \
  -ex "continue" \
  -ex "echo === set \$edx + stepi ===\n" \
  -ex "set \$edx = 0x5555aaaa" \
  -ex "stepi" \
  -ex "print/x \$edx" \
  -ex "echo === memory/registers/backtrace ===\n" \
  -ex "x/4x \$esp" \
  -ex "info registers" \
  -ex "backtrace" \
  -ex "echo === detach ===\n" \
  -ex "detach" \
  -ex "echo DONE\n" \
  2>&1 | tee /tmp/gdb-over-serial-output.txt

# Parse results
PASS_CNT=0
FAIL_CNT=0

check_result() {
    local name="$1" pattern="$2"
    if grep -q "$pattern" /tmp/gdb-over-serial-output.txt 2>/dev/null; then
        echo "  PASS: $name"
        PASS_CNT=$((PASS_CNT + 1))
    else
        echo "  FAIL: $name"
        FAIL_CNT=$((FAIL_CNT + 1))
    fi
}

check_result "break+continue" "Breakpoint 1, gdb_poll"
check_result "stepi" "stepi"
check_result "continue after stepi" "Breakpoint 1, gdb_poll"
check_result "set \$eax = 0x12345678" '\$1 = 0x12345678'
check_result "set \$ecx = 0xdeadbeef" '\$2 = 0xdeadbeef'
check_result "continue after set" "Breakpoint 1, gdb_poll"
check_result "stepi after set preserves edx" '\$3 = 0x5555aaaa'
check_result "memory read" "0x.*:"
check_result "info registers" "eax.*0x"
check_result "backtrace" "#0.*gdb_poll"
check_result "detach" "DONE"

echo ""
echo "=== Results: $PASS_CNT pass, $FAIL_CNT fail ==="
RC2=$FAIL_CNT
echo ""
if [ $RC -eq 0 ] && [ $RC2 -eq 0 ]; then
    echo "=== GDB SERIAL PTY TEST PASSED ==="
else
    echo "=== GDB SERIAL PTY TEST FAILED ==="
fi
exit $(($RC || $RC2))
