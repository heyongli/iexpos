#!/bin/bash
# Dependency check/install for building and testing iexpos.
#
# Usage:
#     ./tools/check-deps.sh             # check only
#     ./tools/check-deps.sh --install   # install missing packages (needs sudo)
#
# Checks:
#   build tools: make, gcc, ld, nasm, qemu-img
#   test tools:  qemu-system-x86_64, gdb, socat, python3, ss, fuser
#   kvm access:  /dev/kvm writable (user in kvm group)
set -e

cd "$(dirname "$0")/.."
INSTALL=0
[ "$1" = "--install" ] && INSTALL=1

read -r -d '' TOOLS <<'EOF' || true
make|make
gcc|gcc
ld|binutils
nasm|nasm
qemu-system-x86_64|qemu-system-x86
qemu-img|qemu-system-x86
gdb|gdb
socat|socat
python3|python3
ss|iproute2
fuser|psmisc
EOF

missing=""
while IFS='|' read -r cmd pkg; do
    [ -z "$cmd" ] && continue
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "OK   $cmd"
    else
        echo "MISS $cmd (package: $pkg)"
        missing="$missing $pkg"
    fi
done <<<"$TOOLS"

if [ -n "$missing" ]; then
    if [ "$INSTALL" -eq 1 ]; then
        echo ""
        echo "Installing missing packages: $missing"
        sudo apt-get update
        sudo apt-get install -y $missing
    else
        echo ""
        echo "Missing packages: $missing"
        echo "Install with: sudo apt-get install -y $missing"
    fi
fi

echo ""
if [ -e /dev/kvm ]; then
    if [ -w /dev/kvm ]; then
        echo "OK   KVM access (/dev/kvm writable)"
    else
        echo "WARN /dev/kvm exists but not writable for user '$USER'"
        if [ "$INSTALL" -eq 1 ]; then
            sudo usermod -aG kvm "$USER"
            echo "  Added '$USER' to group 'kvm'."
            echo "  IMPORTANT: log out and back in (or restart WSL) for it to take effect."
        else
            echo "  Fix: sudo usermod -aG kvm $USER, then re-login"
        fi
    fi
else
    echo "WARN /dev/kvm does not exist (KVM unavailable; tests fall back to slow TCG)"
fi

if [ -n "$missing" ]; then
    exit 1
fi
exit 0
