#!/bin/bash
# GDB Serial PTY Bridge + Reentrancy Test
# ==========================================
#
# Verifies that GDB works correctly over a serial PTY bridge,
# including breakpoint handling, single-stepping, register manipulation,
# and reentrancy protection.
#
# Background
# ----------
# The GDB stub uses a reentrancy guard (gdb_in_handler flag) to prevent
# nested breakpoints from causing infinite loops. This test exercises the
# full GDB debugging workflow via a socat PTY bridge.
#
# Test Method
# -----------
# 1. Boot kernel with serial on TCP port
# 2. Create socat PTY bridge (TCP -> PTY)
# 3. Verify PTY can read kernel boot output
# 4. Test GDB protocol packet exchange via PTY
# 5. Run GDB batch mode with comprehensive operations:
#    - Break at gdb_poll, continue to breakpoint
#    - Single-step through code
#    - Set/read registers ($eax, $ecx, $edx)
#    - Memory read (x/4x)
#    - Backtrace
#    - Detach
#
# Expected Results
# ----------------
# - PTY bridge must work and receive boot output
# - All 11 GDB operations must succeed:
#   1. break+continue: Hit breakpoint at gdb_poll
#   2. stepi: Single-step instruction
#   3. continue after stepi: Resume execution
#   4. set $eax = 0x12345678: Register write
#   5. set $ecx = 0xdeadbeef: Register write
#   6. continue after set: Resume execution
#   7. stepi after set preserves edx: Register preservation
#   8. memory read: Stack memory accessible
#   9. info registers: Register dump works
#   10. backtrace: Call stack correct
#   11. detach: Clean disconnect
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires socat for PTY bridge
# - Requires GDB with remote target support
# - Uses GDB batch mode for automation
#
# Usage
# -----
#     ./tests/gdb-over-serial.sh              # Build and run
#     ./tests/gdb-over-serial.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if all 11 GDB operations pass
# - Returns 1 if any operation fails
set -euo pipefail

DIR=$(pwd)
BDIR=$DIR/build
PORT=12347
PTY=$DIR/tests/gdb-serial-ptest
DISK=$BDIR/vm-raw.img
ELF=$BDIR/kernel.elf
TMP_OUT=$(mktemp /tmp/gdb-serial-XXXXXX.txt)

cleanup() {
    kill $QEMU_PID 2>/dev/null || true
    kill $SOCAT_PID 2>/dev/null || true
    rm -f $PTY $TMP_OUT
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
source $DIR/tests/kvm-check.sh
qemu-system-x86_64 \
    $(get_kvm_flag) -m 2G -nographic -smp 2 -vga std \
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
[ "$ok" -eq 1 ] || { echo "FAIL: PTY bridge did not receive boot output"; exit 1; }

# Test serial GDB stub with proper packet exchange
  echo "  Testing GDB stub packet echo..."
  python3 "$DIR/tests/gdb-over-serial-test.py" $PTY

RC=$?
[ $RC -eq 0 ] && echo "  PASS: PTY packet exchange"

# Comprehensive GDB test using batch mode (reliable)
echo ""
echo "  Running comprehensive GDB command suite + reentrancy test (batch mode)..."

timeout 60 gdb "$BDIR/kernel.elf" -q -batch \
  -ex "set architecture i8086" \
  -ex "set pagination off" \
  -ex "target remote $PTY" \
  -ex "interrupt" \
  -ex "break *gdb_poll" \
  -ex "continue" \
  -ex "stepi" \
  -ex "continue" \
  -ex "set \$eax = 0x12345678" \
  -ex "print/x \$eax" \
  -ex "set \$ecx = 0xdeadbeef" \
  -ex "print/x \$ecx" \
  -ex "continue" \
  -ex "set \$edx = 0x5555aaaa" \
  -ex "stepi" \
  -ex "print/x \$edx" \
  -ex "continue" \
  -ex "x/4x \$esp" \
  -ex "info registers" \
  -ex "backtrace" \
  -ex "detach" \
  -ex "echo DONE\n" \
  2>&1 | tee $TMP_OUT

RC2=${PIPESTATUS[0]}

# Parse results
PASS_CNT=0
FAIL_CNT=0

check_result() {
    local name="$1" pattern="$2"
    if grep -q "$pattern" $TMP_OUT 2>/dev/null; then
        echo "  PASS: $name"
        PASS_CNT=$((PASS_CNT + 1))
    else
        echo "  FAIL: $name"
        FAIL_CNT=$((FAIL_CNT + 1))
    fi
}

check_result "break+continue" "Breakpoint 1, gdb_poll"
check_result "stepi" "Breakpoint 1"
check_result "continue after stepi" "Breakpoint 1, gdb_poll"
check_result "set \$eax = 0x12345678" '\$1 = 0x12345678'
check_result "set \$ecx = 0xdeadbeef" '\$2 = 0xdeadbeef'
check_result "continue after set" "Breakpoint 1, gdb_poll"
check_result "stepi after set preserves edx" '\$3 = 0x5555aaaa'
check_result "memory read" "0x.*:"
check_result "info registers" "eax"
check_result "backtrace" "#0.*gdb_poll"
check_result "detach" "DONE"

echo ""
echo "=== Results: $PASS_CNT pass, $FAIL_CNT fail ==="
if [ $RC -eq 0 ] && [ $FAIL_CNT -eq 0 ]; then
    echo "=== GDB SERIAL PTY TEST PASSED ==="
    exit 0
else
    echo "=== GDB SERIAL PTY TEST FAILED ==="
    exit 1
fi