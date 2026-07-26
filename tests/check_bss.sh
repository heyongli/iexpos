#!/bin/bash
# Test: kernel memory layout — BSS must not overlap VGA legacy hole (0xA0000–0xBFFFF).
set -e

DIR=/home/radio/iexpos
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
