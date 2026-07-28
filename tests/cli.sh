#!/bin/bash
# CLI Serial Interaction Test
# ============================
#
# Verifies that the built-in CLI responds to serial commands correctly.
#
# Test Method
# -----------
# 1. Boot kernel with serial on TCP port
# 2. Wait for CLI to be ready
# 3. Send commands via serial and verify responses:
#    - help → "Commands:" list
#    - info → "Resolution:" info
#    - echo <text> → echoed back
#    - hex <n> → hex representation
#
# Expected Results
# ----------------
# - All 4 command tests must pass
#
# Usage
# -----
#     ./tests/cli.sh              # Build and run
#     ./tests/cli.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 if all tests pass
# - Returns 1 if any test fails
set -e
cd "$(dirname "$0")/.."

DIR=$(pwd)
BDIR=build
PORT=12355

cleanup() { kill $QEMU_PID 2>/dev/null || true; fuser -k "$PORT"/tcp 2>/dev/null || true; }
trap cleanup EXIT

if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -sC "$DIR" clean all 2>&1 | tail -3
fi

echo ""
echo "=== CLI serial test ==="

source "$DIR/tests/kvm-check.sh"

fuser -k "$PORT"/tcp 2>/dev/null || true
sleep 0.5
qemu-system-x86_64 \
    $(get_kvm_flag) -m 2G -nographic -smp 2 -vga std \
    -drive file="$BDIR/vm-raw.img",format=raw \
    -net none \
    -serial tcp::"$PORT",server,nowait \
    -monitor none \
    >/dev/null 2>&1 &
QEMU_PID=$!

for i in $(seq 1 50); do
    ss -ltn 2>/dev/null | grep -q ":$PORT " && break
    sleep 0.1
done
ss -ltn 2>/dev/null | grep -q ":$PORT " || { echo "FAIL: TCP port did not open"; exit 1; }

python3 <<'PYEOF' 2>&1
import socket, time

PORT = 12355

def send_recv(s, cmd, wait=2.0, timeout=5.0):
    s.sendall((cmd + '\n').encode())
    time.sleep(wait)
    resp = b''
    s.settimeout(timeout)
    try:
        while True:
            d = s.recv(4096)
            if not d:
                break
            resp += d
    except (socket.timeout, BlockingIOError):
        pass
    s.settimeout(10)
    return resp.decode('ascii', errors='replace')

s = socket.socket()
s.settimeout(10)
s.connect(('localhost', PORT))

# Drain boot output and wait for CLI prompt
buf = b''
deadline = time.time() + 12
try:
    while b'$ ' not in buf and time.time() < deadline:
        d = s.recv(4096)
        if not d:
            break
        buf += d
except socket.timeout:
    pass

if b"CLI ready" not in buf:
    # Might not see prompt (TCP lost early output), try sending a command
    time.sleep(1)
else:
    time.sleep(0.5)

ok = 0
total = 4

# Test 1: help
r = send_recv(s, 'help')
if 'Commands:' in r and 'help' in r:
    print("PASS: help command")
    ok += 1
else:
    print(f"FAIL: help got '{r[:200]}'")

# Test 2: info
r = send_recv(s, 'info')
if 'Resolution:' in r:
    print("PASS: info command")
    ok += 1
else:
    print(f"FAIL: info got '{r[:200]}'")

# Test 3: echo
r = send_recv(s, 'echo hello world')
if 'hello world' in r:
    print("PASS: echo command")
    ok += 1
else:
    print(f"FAIL: echo got '{r[:200]}'")

# Test 4: hex
r = send_recv(s, 'hex 255')
if 'ff' in r.lower():
    print("PASS: hex command")
    ok += 1
else:
    print(f"FAIL: hex got '{r[:200]}'")

s.close()
print(f"=== Results: {ok}/{total} passed ===")
exit(0 if ok == total else 1)
PYEOF

RC=$?
if [ "$RC" -eq 0 ]; then
    echo "=== CLI TEST PASSED ==="
else
    echo "=== CLI TEST FAILED ==="
fi
exit $RC
