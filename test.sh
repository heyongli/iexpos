#!/bin/bash
# Runner: executes all test suites in tests/
set -e

DIR=~/iexpos

echo "============================================"
echo "  Building kernel"
echo "============================================"
make -C $DIR clean all 2>&1 | tail -5

echo ""
echo "============================================"
echo "  Running: serial output tests"
echo "============================================"
tests/serial.sh --no-build

echo ""
echo "============================================"
echo "  Running: serial read/write tests"
echo "============================================"
tests/serial-rw.sh --no-build

echo ""
echo "============================================"
echo "  Running: console output tests"
echo "============================================"
tests/console.sh --no-build

echo ""
echo "============================================"
echo "  Running: VGA/VBE initialization tests"
echo "============================================"
tests/vga.sh --no-build

echo ""
echo "============================================"
echo "  Running: visual output tests"
echo "============================================"
tests/visual.sh --no-build

echo ""
echo "============================================"
echo "  Running: RTC time read tests"
echo "============================================"
tests/rtc.sh --no-build

echo ""
echo "============================================"
echo "  Running: IO abort mechanism tests"
echo "============================================"
tests/io-abort.sh --no-build

echo ""
echo "============================================"
echo "  Running: GDB single-step tests"
echo "============================================"
tests/gdb-qemu.sh --no-build

echo ""
echo "============================================"
echo "  Running: GDB serial protocol tests"
echo "============================================"
tests/gdb-over-serial-protocol.sh --no-build

echo ""
echo "============================================"
echo "  Running: GDB serial PTY tests"
echo "============================================"
tests/gdb-over-serial.sh --no-build

echo ""
echo "============================================"
echo "  ALL TESTS PASSED"
echo "============================================"
