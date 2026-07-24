#!/bin/bash
set -e

echo "============================================"
echo "  Running: serial output tests"
echo "============================================"
./tests/serial.sh

echo ""
echo "============================================"
echo "  Running: visual output tests"
echo "============================================"
./tests/visual.sh

echo ""
echo "============================================"
echo "  ALL TESTS PASSED"
echo "============================================"
