#!/bin/bash
# GDB Single-Step Debugging Verification Test
# ==============================================
#
# Verifies that GDB debugging via QEMU GDB stub works correctly,
# including breakpoint setting, symbol resolution, single-stepping, and
# backtrace functionality.
#
# Background
# ----------
# QEMU provides a GDB stub that allows debugging the kernel via GDB over TCP.
# This test verifies that the GDB stub is functional and that basic debugging
# operations (breakpoint, continue, step, backtrace) work correctly.
#
# Test Method
# -----------
# 1. Build kernel with debug symbols
# 2. Start QEMU with -gdb tcp::1234 -S (frozen at start)
# 3. Connect GDB and set hardware breakpoint at setup_main
# 4. Continue to breakpoint, verify symbol resolution
# 5. Step into function, verify backtrace
# 6. Continue to completion, verify serial output
#
# Expected Results
# ----------------
# - ELF must have debug info (.debug_info section)
# - GDB must hit breakpoint at setup_main
# - Symbol must resolve to correct function
# - Backtrace must show setup_main in call stack
# - Serial output must complete normally
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires GDB installed
# - Requires kernel with debug symbols
# - Uses GDB batch mode for automation
#
# Usage
# -----
#     ./tests/gdb-qemu.sh              # Build and run test
#     ./tests/gdb-qemu.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if all GDB operations succeed
# - Returns 1 if any GDB operation fails
set -e

DIR=$(pwd)
DISK="${DISK:-$DIR/build/vm-raw.img}"
ELF="${ELF:-$DIR/build/kernel.elf}"
TMP_OUT=$(mktemp /tmp/vm-gdb-output-XXXXXX.txt)
GDB_LOG=$(mktemp /tmp/vm-gdb-log-XXXXXX.txt)

if ! command -v gdb &>/dev/null; then
    echo "  SKIP: gdb not installed"
    exit 0
fi

if [ "$ELF" = "$DIR/build/kernel.elf" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

if ! readelf -S "$ELF" 2>/dev/null | grep -q .debug_info; then
    echo "  FAIL: $ELF missing debug info"
    exit 1
fi
echo "  ELF debug info OK"

echo ""
echo "=== GDB single-step test ==="
source $DIR/tests/kvm-check.sh

timeout 18 qemu-system-x86_64 $(get_kvm_flag) -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT -gdb tcp::1234 -S &
QEMU_PID=$!
sleep 0.5

gdb -batch \
  -ex "file $ELF" \
  -ex "set architecture i386:x86-64" \
  -ex "target remote localhost:1234" \
  -ex "hbreak setup_main" \
  -ex "continue" \
  -ex "backtrace" \
  -ex "step" \
  -ex "continue" \
  > $GDB_LOG 2>&1 || true
cat $GDB_LOG

kill $QEMU_PID 2>/dev/null || true
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

check "Break at setup_main"     "hit Breakpoint 1,.*setup_main"  "$GDB_LOG"
check "Single-step after setup" "setup_main () at"              "$GDB_LOG"
check "Backtrace printed"       "#0.*setup_main"                "$GDB_LOG"
check "Serial output complete"  "Graphics test complete"        "$TMP_OUT"

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