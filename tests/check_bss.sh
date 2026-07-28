#!/bin/bash
# Kernel Memory Layout Test - BSS Segment Verification
# =====================================================
#
# Verifies that the kernel's BSS (Block Started by Symbol) segment
# does not overlap with the VGA legacy memory hole (0xA0000-0xBFFFF).
#
# Background
# ----------
# In x86 real mode, the VGA graphics memory is mapped to 0xA0000-0xBFFFF.
# If the kernel's BSS segment overlaps this region, data written to BSS would
# corrupt VGA memory, causing display artifacts or system crashes.
#
# Test Method
# -----------
# 1. Extract BSS start and end addresses from kernel.elf using nm
# 2. Check if BSS range overlaps VGA hole (0xA0000-0xBFFFF)
# 3. Specifically verify draw_buf pointer is not in VGA hole
#
# Expected Results
# ----------------
# - BSS must be entirely below 0xA0000 or entirely above 0xBFFFF
# - draw_buf address must not be in VGA hole range
# - Output must show "PASS: memory layout is safe"
#
# Environment
# -----------
# - Requires kernel.elf to be built first (make)
# - Uses nm to extract symbol addresses from ELF
#
# Usage
# -----
#     ./tests/check_bss.sh
#
# Exit Status
# -----------
# - Returns 0 if memory layout is safe (no overlap)
# - Returns 1 if BSS overlaps VGA hole or draw_buf is in VGA hole
set -e

DIR=$(pwd)
ELF=$DIR/build/kernel.elf

if [ ! -f "$ELF" ]; then
    echo "  FAIL: $ELF not found — build first"
    exit 1
fi

# Get BSS start and end addresses from nm
BSS_START=$(nm -n "$ELF" | grep ' __bss_start' | head -1 | awk '{print "0x"$1}')
BSS_END=$(nm -n "$ELF" | grep ' _end' | head -1 | awk '{print "0x"$1}')

if [ -z "$BSS_START" ] || [ -z "$BSS_END" ]; then
    echo "  FAIL: could not find BSS symbols in kernel.elf"
    exit 1
fi

VGA_HOLE_START=$((0xA0000))
VGA_HOLE_END=$((0xBFFFF))

BSS_START_DEC=$((BSS_START))
BSS_END_DEC=$((BSS_END))

echo "  BSS range : $(printf '0x%X' $BSS_START_DEC) – $(printf '0x%X' $BSS_END_DEC)"
echo "  VGA hole  : 0xA0000 – 0xBFFFF"

# Check: BSS must not overlap VGA hole
if [ "$BSS_START_DEC" -le "$VGA_HOLE_END" ] && [ "$BSS_END_DEC" -ge "$VGA_HOLE_START" ]; then
    echo "  FAIL: BSS range overlaps VGA legacy memory hole"
    echo "  Data in BSS that falls in 0xA0000–0xBFFFF is routed to VGA memory, not system RAM."
    exit 1
fi

# Also check draw_buf specifically (should be a pointer in .data, not a large array in .bss)
DRAW_BUF_INFO=$(nm -n "$ELF" | grep ' draw_buf' | head -1)
DRAW_BUF_ADDR=$(echo "$DRAW_BUF_INFO" | awk '{print "0x"$1}')

if [ -n "$DRAW_BUF_ADDR" ]; then
    DRAW_BUF_DEC=$((DRAW_BUF_ADDR))
    if [ "$DRAW_BUF_DEC" -ge "$VGA_HOLE_START" ] && [ "$DRAW_BUF_DEC" -le "$VGA_HOLE_END" ]; then
        echo "  FAIL: draw_buf at $DRAW_BUF_ADDR falls in VGA hole"
        exit 1
    fi
    echo "  draw_buf  : $DRAW_BUF_ADDR (OK)"
fi

echo "  PASS: memory layout is safe"