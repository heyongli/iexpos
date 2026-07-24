#!/bin/bash
# Test: GDB single-step through C entry, verify symbols and stepping work
set -e

DIR=/home/radio/iexpos
DISK=$DIR/build/vm-raw.img
TMP_OUT=/tmp/vm-gdb-output.txt
GDB_LOG=/tmp/vm-gdb-log.txt

if ! command -v gdb &>/dev/null; then
    echo "  SKIP: gdb not installed"
    exit 0
fi

echo "=== Building ==="
make -C $DIR clean all 2>&1 | tail -3

# Verify ELF has debug info
if ! readelf -S $DIR/build/kernel.elf 2>/dev/null | grep -q .debug_info; then
    echo "  FAIL: kernel.elf missing debug info"
    exit 1
fi
echo "  ELF debug info OK"

echo ""
echo "=== GDB single-step test ==="

# Start QEMU with GDB server in background
timeout 10 qemu-system-x86_64 -m 2G -nographic -smp 2 -vga std \
  -hda $DISK -net none -serial file:$TMP_OUT -s -S &
QEMU_PID=$!
sleep 0.5

# GDB batch commands
gdb -batch \
  -ex "file $DIR/build/kernel.elf" \
  -ex "target remote localhost:1234" \
  -ex "break setup_main" \
  -ex "continue" \
  -ex "backtrace" \
  -ex "print bm_ui_width()" \
  -ex "step" \
  -ex "list" \
  -ex "break demo_orbit" \
  -ex "continue" \
  -ex "backtrace" \
  -ex "print cols[0]" \
  -ex "continue" \
  $DIR/build/kernel.elf 2>&1 | tee $GDB_LOG

# Wait for QEMU to finish (timeout will kill it)
wait $QEMU_PID 2>/dev/null || true

echo ""
echo "=== Verifying ==="

PASS=0
FAIL=0

check() {
    local label="$1"
    local pattern="$2"
    local file="$3"
    if grep -q "$pattern" "$file"; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected '$pattern')"
        FAIL=$((FAIL + 1))
    fi
}

check "Break at setup_main"     "Breakpoint.*setup_main"  "$GDB_LOG"
check "Single-step after setup" "setup_main () at"        "$GDB_LOG"
check "Break at demo_orbit"     "Breakpoint.*demo_orbit"  "$GDB_LOG"
check "Serial output complete"  "Graphics test complete"  "$TMP_OUT"

rm -f $TMP_OUT $GDB_LOG

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "=== ALL TESTS PASSED ==="
    exit 0
else
    echo "=== SOME TESTS FAILED ==="
    exit 1
fi
