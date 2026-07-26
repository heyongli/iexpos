#!/bin/bash
# Test: VGA/VBE initialization
# Verifies framebuffer is initialized with valid resolution
set -e

DIR=~/iexpos
DISK=$DIR/build/vm-raw.img
TMP_OUT=/tmp/vm-vga.txt

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi

echo ""
echo "=== Booting VM (VGA test) ==="
timeout 12 qemu-system-x86_64 -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw -net none -serial file:$TMP_OUT 2>/dev/null

echo ""
echo "=== Verifying VGA/VBE ==="

PASS=0
FAIL=0

# Check resolution is valid (non-zero)
RES_LINE=$(grep "Resolution:" $TMP_OUT | head -1)
if [ -n "$RES_LINE" ]; then
    # Extract width, height, bpp
    WIDTH=$(echo "$RES_LINE" | grep -oE '[0-9]+x[0-9]+x[0-9]+' | cut -d'x' -f1)
    HEIGHT=$(echo "$RES_LINE" | grep -oE '[0-9]+x[0-9]+x[0-9]+' | cut -d'x' -f2)
    BPP=$(echo "$RES_LINE" | grep -oE '[0-9]+x[0-9]+x[0-9]+' | cut -d'x' -f3)
    
    if [ -n "$WIDTH" ] && [ "$WIDTH" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Width is valid ($WIDTH)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Width is invalid"
        FAIL=$((FAIL + 1))
    fi
    
    if [ -n "$HEIGHT" ] && [ "$HEIGHT" -gt 0 ] 2>/dev/null; then
        echo "  PASS: Height is valid ($HEIGHT)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Height is invalid"
        FAIL=$((FAIL + 1))
    fi
    
    if [ -n "$BPP" ] && [ "$BPP" -gt 0 ] 2>/dev/null; then
        echo "  PASS: BPP is valid ($BPP)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: BPP is invalid"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: Resolution line not found"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "=== VGA TEST PASSED ==="
    rm -f $TMP_OUT
    exit 0
else
    echo "=== VGA TEST FAILED ==="
    rm -f $TMP_OUT
    exit 1
fi
