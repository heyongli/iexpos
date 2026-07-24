#!/bin/bash
# Runner: executes all test suites in tests/
set -e

echo "============================================"
echo "  Running: serial output tests"
echo "============================================"
tests/serial.sh

echo ""
echo "============================================"
echo "  Running: serial read/write tests"
echo "============================================"
tests/serial-rw.sh

echo ""
echo "============================================"
echo "  Running: visual output tests"
echo "============================================"
tests/visual.sh

echo ""
echo "============================================"
echo "  Running: GDB single-step tests"
echo "============================================"
tests/gdb-qemu.sh

echo ""
echo "============================================"
echo "  Running: serial GDB stub tests"
echo "============================================"
tests/serial-gdb.sh

echo ""
echo "============================================"
echo "  ALL TESTS PASSED"
echo "============================================"
