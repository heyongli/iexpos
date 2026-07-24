#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Serial GDB stub functional test
# QEMU -serial tcp:PORT → Python socket simulates GDB client:
# 1. send '+' → kernel gdb_poll triggers INT3 → stub sends $T05
# 2. send '+$c#63' (ACK + continue) → stub ACKs with '+'
# 3. send '+' again → confirm kernel alive and stub re-enters
set -euo pipefail
cd "$(dirname "$0")/.."

step()  { printf '  %-8s %s\n' "$1" "$2"; }
fail()  { step FAIL "$1"; exit 1; }
pass()  { step PASS "$1"; }

BDIR=build
PORT=12346
KERNEL=$BDIR/kernel.elf

cleanup() { kill $QEMU_PID 2>/dev/null || true; fuser -k "$PORT"/tcp 2>/dev/null || true; }
trap cleanup EXIT

echo "=== Serial GDB stub test ==="

make -sC "$(pwd)" clean all 2>&1 | tail -1
[ -f "$KERNEL" ] || fail "no kernel.elf"
readelf -S "$KERNEL" | grep -q debug_info || fail "no debug info"

fuser -k "$PORT"/tcp 2>/dev/null || true
qemu-system-x86_64 \
    -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -hda "$BDIR/vm-raw.img" \
    -net none \
    -serial tcp::"$PORT",server,nowait \
    >/dev/null 2>&1 &
QEMU_PID=$!

for i in $(seq 1 30); do
    ss -ltn 2>/dev/null | grep -q ":$PORT " && break
    sleep 0.1
done
ss -ltn 2>/dev/null | grep -q ":$PORT " || fail "TCP port did not open"

python3 <<'PYEOF' 2>&1
import socket, time
ok = 0
s = socket.socket()
s.connect(('localhost', 12346))
s.settimeout(15)

# Wait for boot
buf = b''
while b'Graphics test complete' not in buf:
    d = s.recv(4096)
    if not d: break
    buf += d
print("FOUND graphics complete")

time.sleep(0.3)

# Send trigger
s.sendall(b'+')
resp = b''
while b'$T05' not in resp:
    d = s.recv(4096)
    if not d: break
    resp += d
if b'$T05' in resp:
    print("PASS: $T05 after trigger")
    ok += 1
else:
    print("FAIL: no $T05")

# Send continue
s.sendall(b'+$c#63')
time.sleep(0.5)
try:
    d = s.recv(4096)
    if b'+' in d:
        print("PASS: ACK after continue")
        ok += 1
    else:
        print("FAIL: no ACK")
except:
    print("FAIL: no response")

# Verify kernel still alive: trigger again
s.sendall(b'+')
resp = b''
while b'$T05' not in resp:
    d = s.recv(4096)
    if not d: break
    resp += d
if b'$T05' in resp:
    print("PASS: second $T05 (kernel alive)")
    ok += 1
else:
    print("FAIL: kernel dead")

s.close()
print("=== Results: %d passed, %d failed ===" % (ok, 3-ok))
exit(0 if ok == 3 else 1)
PYEOF

RC=$?
kill $QEMU_PID 2>/dev/null || true

[ $RC -eq 0 ] && pass "all checks" || fail "some checks failed"
echo "=== serial GDB test $([ $RC -eq 0 ] && echo PASSED || echo FAILED) ==="
exit $RC
