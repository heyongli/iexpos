#!/bin/bash
# Main Test Suite Runner for iexpos kernel
# =========================================
#
# Executes all test suites in tests/ directory. Each test has its own
# documentation — run 'head -40 tests/<name>.sh' for details.
#
# Test Method
# -----------
# - Each test is a standalone script in tests/ directory
# - Tests run in isolation — failure in one test does NOT stop others
# - Use --no-build flag to skip kernel rebuild (for faster re-runs)
# - All tests use QEMU with KVM acceleration
#
# Environment
# -----------
# - QEMU with KVM support
# - Development tools: make, gcc, nasm, ld
# - GDB, socat, Python 3
#
# Usage
# -----
#     ./test.sh                    # Build kernel and run all tests
#     ./test.sh --no-build         # Run tests without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if ALL tests pass
# - Returns 1 if ANY test fails
set -e

DIR=$(pwd)

echo "============================================"
echo "  Building kernel"
echo "============================================"
make -C $DIR clean all 2>&1 | tail -5

echo ""
echo "============================================"
echo "  Running: kernel memory layout tests"
echo "============================================"
tests/check_bss.sh

echo ""
echo "============================================"
echo "  Running: CLI interaction tests"
echo "============================================"
tests/cli.sh --no-build

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