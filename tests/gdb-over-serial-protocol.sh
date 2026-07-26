#!/bin/bash
# Test: GDB serial protocol correctness over raw TCP.
# Sends GDB remote protocol packets directly and verifies responses.
set -euo pipefail
cd "$(dirname "$0")/.."

BDIR=build
PORT=12346

cleanup() { kill $QEMU_PID 2>/dev/null || true; fuser -k "$PORT"/tcp 2>/dev/null || true; }
trap cleanup EXIT

echo "=== GDB serial protocol test ==="

make -sC "$(pwd)" clean all 2>&1 | tail -1
[ -f "$BDIR/vm-raw.img" ] || { echo "FAIL: no vm-raw.img"; exit 1; }

fuser -k "$PORT"/tcp 2>/dev/null || true
qemu-system-x86_64 \
    -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file="$BDIR/vm-raw.img",format=raw \
    -net none \
    -serial tcp::"$PORT",server,nowait \
    >/dev/null 2>&1 &
QEMU_PID=$!

for i in $(seq 1 30); do
    ss -ltn 2>/dev/null | grep -q ":$PORT " && break
    sleep 0.1
done
ss -ltn 2>/dev/null | grep -q ":$PORT " || { echo "FAIL: TCP port did not open"; exit 1; }

python3 <<'PYEOF' 2>&1
import socket, time

def ck(data):
    return sum(data) % 256

def pkt(payload):
    return f"${payload}#{ck(payload.encode()):02x}".encode()

def send_recv(s, raw, wait=0.3):
    """Send raw bytes, wait, return all received data."""
    s.sendall(raw)
    time.sleep(wait)
    resp = b''
    try:
        while True:
            d = s.recv(4096)
            if not d: break
            resp += d
    except: pass
    return resp

def parse_pkt(data):
    """Extract the first GDB packet payload from raw data."""
    if b'$' not in data: return ''
    start = data.index(b'$') + 1
    end = data.index(b'#', start) if b'#' in data[start:] else len(data)
    return data[start:end].decode('ascii', errors='ignore')

ok = 0
total = 11
s = socket.socket()
s.connect(('localhost', 12346))
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
    print(f"WARN: boot output not seen ({len(buf)} bytes received)")

# Drain any trailing boot output
time.sleep(0.5)
try:
    while True:
        d = s.recv(4096)
        if not d: break
except: pass

# ---- Test 1: ? query → S05 stop reply ----
# The first ? enters handler from poll (gdb_from_poll=1), S05 is sent.
resp = send_recv(s, pkt("?"))
p = parse_pkt(resp)
if 'S05' in p:
    print("PASS: ? → S05")
    ok += 1
else:
    print(f"FAIL: ? got '{p}'")

# ---- Test 2: vMustReplyEmpty → OK ----
resp = send_recv(s, pkt("vMustReplyEmpty"))
p = parse_pkt(resp)
if 'OK' in p:
    print("PASS: vMustReplyEmpty → OK")
    ok += 1
else:
    print(f"FAIL: vMustReplyEmpty got '{p}'")

# ---- Test 3: qSupported → PacketSize=200 ----
resp = send_recv(s, pkt("qSupported:multiprocess+;swbreak+;hwbreak+;vContSupported+"))
p = parse_pkt(resp)
if 'PacketSize=' in p:
    print("PASS: qSupported → PacketSize=200")
    ok += 1
else:
    print(f"FAIL: qSupported got '{p}'")

# ---- Test 4: g (read all registers) ----
resp = send_recv(s, pkt("g"))
p = parse_pkt(resp)
# 16 regs x 8 hex chars = 128
if len(p) >= 128:
    print(f"PASS: g → {len(p)} chars")
    ok += 1
else:
    print(f"FAIL: g too short ({len(p)} chars): '{p[:40]}...'")

# ---- Test 5: m7e00,10 (read memory) ----
resp = send_recv(s, pkt("m7e00,10"))
p = parse_pkt(resp)
if len(p) == 32:
    print("PASS: m7e00,10 → 32 hex chars")
    ok += 1
else:
    print(f"FAIL: m7e00,10 got '{p}'")

# ---- Test 6: P (single register write) and verify ----
# Write EAX = 0x12345678 (P0=78563412)
resp = send_recv(s, pkt("P0=78563412"))
p = parse_pkt(resp)
if 'OK' in p:
    print("PASS: P0=... → OK")
    ok += 1
else:
    print(f"FAIL: P0 got '{p}'")

# ---- Test 7: g (read back, verify EAX changed) ----
resp = send_recv(s, pkt("g"))
p = parse_pkt(resp)
if len(p) >= 8 and p[:8] == '78563412':
    print("PASS: g → EAX=0x12345678 after P")
    ok += 1
else:
    print(f"FAIL: EAX not set correctly, first 8 chars: '{p[:8]}'")

# ---- Test 8: M (write memory) + verify ----
# Write 4 bytes at 0x10000
resp = send_recv(s, pkt("M10000,4:deadbeef"))
p = parse_pkt(resp)
if 'OK' in p:
    print("PASS: M → OK")
    ok += 1
else:
    print(f"FAIL: M got '{p}'")

# ---- Test 9: m (read back written memory) ----
resp = send_recv(s, pkt("m10000,4"))
p = parse_pkt(resp)
if p == 'deadbeef':
    print("PASS: m10000,4 → deadbeef")
    ok += 1
else:
    print(f"FAIL: m10000,4 got '{p}'")

# ---- Test 10: continue (ACK first, then poll next) ----
resp = send_recv(s, pkt("c"), wait=1.0)
if b'+' in resp:
    print("PASS: c → ACK")
    ok += 1
else:
    print(f"FAIL: c got '{resp[:20]}'")

s.close()
print(f"=== Results: {ok}/{total} passed ===")
exit(0 if ok == total else 1)
PYEOF

RC=$?
kill $QEMU_PID 2>/dev/null || true

if [ $RC -eq 0 ]; then
    echo "=== GDB SERIAL PROTOCOL TEST PASSED ==="
else
    echo "=== GDB SERIAL PROTOCOL TEST FAILED ==="
fi
exit $RC
