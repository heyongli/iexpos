#!/bin/bash
# GDB Reentrancy Guard Verification Test
# ========================================
#
# Verifies that the GDB reentrancy guard works correctly when
# a breakpoint is set at the gdb_handler entry point, preventing nested
# breakpoints from causing infinite loops.
#
# Background
# ----------
# When the GDB stub processes a packet, it sets gdb_in_handler=1 before
# calling gdb_handler. If a breakpoint is set at gdb_handler entry, the
# INT3 interrupt triggers re-entry. The reentrancy guard detects this and
# sets TF (trap flag) to single-step out of the nested handler.
#
# Test Method
# -----------
# 1. Boot kernel with serial on TCP port
# 2. Get gdb_handler address from kernel symbols (nm)
# 3. Raw socket GDB protocol:
#    a. Send "?" -> expect S05 (clean handler start)
#    b. Send "Z0,<addr>,1" -> expect OK (set bp at handler)
#    c. Send "c" -> expect ACK (continue, triggers reentry)
#    d. Send "?" -> expect S05 (reentry survived)
#    e. Send "g" -> expect 128 hex chars (registers readable)
#    f. Send "c;?" -> expect S05 (responsive after 2nd continue)
#
# Expected Results
# ----------------
# - All 7 checks must pass (1 boot + 6 protocol steps)
# - Critical check: "?" after breakpoint -> S05 (reentrancy guard works)
# - If guard fails, kernel hangs and returns empty
#
# Environment
# -----------
# - Requires QEMU with KVM support
# - Requires Python 3 for socket communication
# - Uses raw TCP socket for GDB protocol
#
# Usage
# -----
#     ./tests/gdb-over-serial-reentrancy.sh              # Build and run
#     ./tests/gdb-over-serial-reentrancy.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if all 7 checks pass
# - Returns 1 if any check fails (reentrancy guard broken)
set -euo pipefail

DIR=$(pwd)
BDIR=$DIR/build
PORT=12350
DISK=$BDIR/vm-raw.img

cleanup() {
    kill ${QEMU_PID:-} 2>/dev/null || true
    fuser -k "$PORT"/tcp 2>/dev/null || true
}
trap cleanup EXIT

echo "=== GDB reentrancy test ==="

make -sC $DIR clean all 2>&1 | tail -1
[ -f "$DISK" ] || { echo "FAIL: no vm-raw.img"; exit 1; }

fuser -k "$PORT"/tcp 2>/dev/null || true

echo "  Starting QEMU (serial tcp::$PORT)..."
qemu-system-x86_64 \
    -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw \
    -net none \
    -serial tcp::"$PORT",server,nowait \
    >/dev/null 2>&1 &
QEMU_PID=$!

echo "  Waiting for QEMU serial port..."
for i in $(seq 1 30); do
    ss -ltn 2>/dev/null | grep -q ":$PORT " && break
    sleep 0.1
done
ss -ltn 2>/dev/null | grep -q ":$PORT " || { echo "FAIL: TCP port did not open"; exit 1; }
echo "  TCP port open"

# Get gdb_handler address from the ELF
GDB_HANDLER_ADDR=$(nm "$BDIR/kernel.elf" | grep ' gdb_handler$' | awk '{print $1}')
GDB_SEND_ADDR=$(nm "$BDIR/kernel.elf" | grep ' gdb_send$' | awk '{print $1}')
echo "  gdb_handler @ 0x$GDB_HANDLER_ADDR"
echo "  gdb_send    @ 0x$GDB_SEND_ADDR"

python3 <<PYEOF 2>&1
import socket, time, struct

def ck(data):
    return sum(data) % 256

def pkt(payload):
    return f"\${payload}#{ck(payload.encode()):02x}".encode()

def send_recv(s, data, wait=0.5):
    s.sendall(data)
    time.sleep(wait)
    resp = b''
    s.settimeout(2)
    try:
        while True:
            d = s.recv(4096)
            if not d: break
            resp += d
            if b'#' in resp: break
    except: pass
    s.settimeout(15)
    return resp

def parse_pkt(data):
    if b'$' not in data: return ''
    start = data.index(b'$') + 1
    end = data.index(b'#', start) if b'#' in data[start:] else len(data)
    return data[start:end].decode('ascii', errors='ignore')

def parse_ack(data):
    return b'+' in data

ok = 0
total = 7

s = socket.socket()
s.connect(('localhost', $PORT))
s.settimeout(15)

# Drain boot output
buf = b''
deadline = time.time() + 12
try:
    while b'Graphics test complete' not in buf and time.time() < deadline:
        d = s.recv(4096)
        if not d: break
        buf += d
except socket.timeout:
    pass

if b'Graphics test complete' in buf:
    print("PASS: boot output received")
    ok += 1
else:
    print(f"WARN: boot output not seen ({len(buf)} bytes)")

s.settimeout(0.5)
time.sleep(0.2)
try:
    while True:
        d = s.recv(4096)
        if not d: break
except: pass
s.settimeout(15)

# ---- Test 1: ? query → enters handler, sends S05 ----
resp = send_recv(s, pkt("?"))
p = parse_pkt(resp)
if 'S05' in p:
    print("PASS: ? → S05")
    ok += 1
else:
    print(f"FAIL: ? got '{p}'")

# ---- Test 2: Set breakpoint at gdb_handler (Z0) ----
bp_addr = int('$GDB_HANDLER_ADDR', 16)
bp_cmd = f"Z0,{bp_addr:x},1"
resp = send_recv(s, pkt(bp_cmd))
p = parse_pkt(resp)
if 'OK' in p:
    print(f"PASS: Z0 at 0x{bp_addr:x} → OK")
    ok += 1
else:
    print(f"FAIL: Z0 got '{p}'")

# ---- Test 3: continue (c) → ACK ----
resp = send_recv(s, pkt("c"), wait=0.3)
if parse_ack(resp):
    print("PASS: c → ACK")
    ok += 1
else:
    print(f"FAIL: c got '{resp[:20]}'")

# Wait for target to run and poll serial
time.sleep(0.3)

# ---- Test 4: Send ? again → triggers gdb_poll → int3 → gdb_handler (0xCC!) ----
resp = send_recv(s, pkt("?"), wait=1.0)
p = parse_pkt(resp)
if 'S05' in p:
    print("PASS: ? after breakpoint → S05 (reentrancy guard works)")
    ok += 1
else:
    print(f"FAIL: ? after breakpoint got '{p}' (raw={resp[:40]})")

# ---- Test 5: Read registers (g) → 128 chars ----
resp = send_recv(s, pkt("g"))
p = parse_pkt(resp)
if len(p) >= 128:
    print("PASS: g → 128 chars (state preserved)")
    ok += 1
else:
    print(f"FAIL: g too short ({len(p)} chars)")

# ---- Test 6: Continue and verify responsive ----
resp = send_recv(s, pkt("c"), wait=0.5)
if parse_ack(resp):
    time.sleep(0.3)
    resp = send_recv(s, pkt("?"), wait=1.0)
    p = parse_pkt(resp)
    if 'S05' in p:
        print("PASS: c+? → S05 (still responsive)")
        ok += 1
    else:
        print(f"FAIL: c+? got '{p}'")
else:
    print(f"FAIL: c got '{resp[:20]}'")

s.close()
print(f"=== Results: {ok}/{total} passed ===")
exit(0 if ok == total else 1)
PYEOF

RC=$?

if [ $RC -eq 0 ]; then
    echo "=== GDB REENTRANCY TEST PASSED ==="
else
    echo "=== GDB REENTRANCY TEST FAILED ==="
fi
exit $RC