#!/bin/bash
# KVM Detection Helper
# ====================
#
# Provides get_kvm_flag() function for test scripts.
# Returns "-enable-kvm" if KVM is available, empty string otherwise.
#
# Usage:
#     source tests/kvm-check.sh
#     qemu-system-x86_64 $(get_kvm_flag) ...

get_kvm_flag() {
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "-enable-kvm"
    fi
}
