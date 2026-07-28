#!/usr/bin/env python3
"""
GDB Serial PTY Packet Exchange Test
====================================

Verifies that the GDB stub responds correctly to a basic packet
over a serial PTY bridge.

Summary
-------
Sends a "?" query packet via the PTY and checks for an "S05" (stop reply)
response from the GDB stub running in the kernel.

Background
----------
The kernel's GDB stub processes packets received on the serial port.
The "?" command is the simplest query that should always return "S05"
indicating the target is stopped. This test validates the PTY bridge
(socat) and GDB stub communication path.

Usage
-----
    python3 gdb-over-serial-test.py <pty_path>

    Example:
        python3 gdb-over-serial-test.py /tmp/gdb-serial-ptest

Expected Output
---------------
    PASS: ? -> S05 via PTY

Exit Status
-----------
    Returns 0 if S05 response received.
    Returns 1 if no response or unexpected response.
"""

import os, time, sys


def main():
    """Main entry point.

    Args:
        sys.argv[1]: Path to the PTY device file.

    Returns:
        0 on success, 1 on failure.
    """
    pty_path = sys.argv[1]

    fd = os.open(pty_path, os.O_RDWR | os.O_NONBLOCK)

    # First switch from CLI to GDB mode
    os.write(fd, b'gdb\n')
    time.sleep(1.0)

    # Drain any response
    deadline = time.time() + 2
    while time.time() < deadline:
        try:
            d = os.read(fd, 4096)
            if not d: break
        except: pass
        time.sleep(0.1)

    # Send ? packet via PTY - triggers gdb_poll, handler processes ?
    os.write(fd, b'$?#3f')
    time.sleep(0.5)

    resp = b''
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            d = os.read(fd, 4096)
            if d: resp += d
            if b'S05' in resp: break
        except: pass
        time.sleep(0.1)

    os.close(fd)
    if b'S05' in resp:
        print("PASS: ? -> S05 via PTY")
        return 0
    else:
        print("FAIL: no S05 after ?")
        return 1


if __name__ == "__main__":
    exit(main())