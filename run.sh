#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building ==="
make -C "$DIR" clean all

echo ""
echo "=== Launching QEMU (serial on stdio) ==="
exec sg kvm -c "qemu-system-x86_64 -enable-kvm -m 2G -smp 2 -vga std \
    -hda '$DIR/vm-raw.img' -serial stdio -net none"
