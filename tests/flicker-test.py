#!/usr/bin/env python3
"""
Flicker detection utility for QEMU screendump analysis.

Captures N screendumps via QEMU HMP monitor, then checks the
progress-bar region (bottom 48 rows) for the clear-colour
(0x0f1729) which would indicate the back-buffer was visible
because of a delayed page-flip (flicker).

Environment
-----------
- QEMU with a display backend that supports 'screendump'
  (egl-headless, sdl, gtk, vnc)
- The kernel must be already built (make)
- Serial and monitor ports must be opened by QEMU

Usage
-----
    python3 flicker-test.py \
        --serial-port 12348 \
        --monitor-port 12349 \
        --count 60 \
        --tmpdir /tmp/screens
"""

import socket, time, os, sys, argparse


def wait_for_serial(port: int, timeout: float = 30) -> socket.socket:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s.connect(('127.0.0.1', port))
            s.settimeout(5)
            return s
        except ConnectionRefusedError:
            time.sleep(0.2)
    raise RuntimeError(f"serial port {port} not reachable after {timeout}s")


def wait_for_boot(sock: socket.socket, timeout: float = 25):
    buf = b''
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            if b'Graphics test complete' in buf:
                return
        except socket.timeout:
            break
    print("  WARNING: 'Graphics test complete' not seen on serial, continuing anyway")


def hmp_cmd(mon: socket.socket, cmd: str) -> bytes:
    mon.sendall((cmd + '\n').encode())
    resp = b''
    while b'(qemu) ' not in resp:
        try:
            chunk = mon.recv(4096)
            if not chunk:
                break
            resp += chunk
        except socket.timeout:
            break
    return resp


def probe_screendump(mon_port: int) -> bool:
    """Probe whether QEMU screendump works."""
    try:
        mon = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        mon.settimeout(3)
        mon.connect(('127.0.0.1', mon_port))
        mon.recv(4096)  # discard prompt
        resp = hmp_cmd(mon, 'screendump /dev/null')
        mon.close()
        if b'Error' in resp or b'failed' in resp:
            print(f"  screendump not available: {resp.decode(errors='replace')[:80]}")
            return False
        return True
    except Exception as e:
        print(f"  screendump probe failed: {e}")
        return False


def check_flicker(data: bytes, w: int, h: int, bar_h: int = 48, pad: int = 4) -> bool:
    """Return True if the progress-bar INNER region shows the clear colour.
    Skips the top/bottom pad rows (not redrawn between frames) and the
    leftmost pixel (x=0..pad-1, also not redrawn).
    """
    CLEAR_RGB = bytes([15, 23, 41])  # 0x0f1729
    inner_start = h - bar_h + pad
    inner_end = h - pad
    for row in range(inner_start, inner_end):
        row_start = row * w * 3
        row_data = data[row_start:row_start + w * 3]
        clear_px = 0
        for sx in range(10):
            px = (pad + sx * (w - 2 * pad) // 10) * 3
            if row_data[px:px + 3] == CLEAR_RGB:
                clear_px += 1
        if clear_px >= 9:
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description='QEMU screendump flicker detector')
    parser.add_argument('--serial-port', type=int, default=12348)
    parser.add_argument('--monitor-port', type=int, default=12349)
    parser.add_argument('--count', type=int, default=60,
                        help='number of screendumps to take')
    parser.add_argument('--delay', type=float, default=0.05,
                        help='seconds between screendumps')
    parser.add_argument('--tmpdir', default='/tmp/flicker-screens')
    parser.add_argument('--bar-h', type=int, default=48,
                        help='height of progress bar in pixels')
    args = parser.parse_args()

    os.makedirs(args.tmpdir, exist_ok=True)

    # ---- wait for QEMU boot ----
    print("  Connecting to serial ...")
    ser = wait_for_serial(args.serial_port)
    print("  Waiting for boot ...")
    wait_for_boot(ser)
    print("  Boot detected")

    # ---- probe monitor ----
    print("  Connecting to monitor ...")
    for _ in range(30):
        try:
            mon = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            mon.settimeout(2)
            mon.connect(('127.0.0.1', args.monitor_port))
            mon.close()
            break
        except ConnectionRefusedError:
            time.sleep(0.2)
    else:
        print("FAIL: monitor port not reachable")
        sys.exit(1)

    if not probe_screendump(args.monitor_port):
        print("FAIL: screendump not supported by this QEMU / display backend")
        print("  Try: -display egl-headless, or -vnc :0, or -display sdl")
        sys.exit(2)

    # ---- wait a moment for progress bar to fill ----
    time.sleep(1.0)

    # ---- capture screendumps (persistent monitor connection) ----
    flicker_count = 0
    clean_count = 0
    fail_count = 0

    print(f"  Capturing {args.count} frames ...")

    mon = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    mon.settimeout(10)
    mon.connect(('127.0.0.1', args.monitor_port))
    # synchronize: drain until a clean prompt, then consume its echo
    time.sleep(0.5)
    mon.settimeout(1)
    try:
        while True:
            chunk = mon.recv(65536)
            if not chunk: break
    except socket.timeout:
        pass
    mon.settimeout(10)
    # send a no-op to get a fresh prompt
    hmp_cmd(mon, '')
    # now the next prompt will appear after we send a command

    for i in range(args.count):
        dump_path = os.path.join(args.tmpdir, f'frame-{i:03d}.ppm')

        resp = hmp_cmd(mon, f'screendump {dump_path}')

        if b'Error' in resp or b'failed' in resp:
            print(f"  MON ERROR at {i}: {resp.decode(errors='replace')[:100]}")
            fail_count += 1
            continue

        if not os.path.exists(dump_path):
            # wait up to 1s
            for _ in range(100):
                time.sleep(0.01)
                if os.path.exists(dump_path):
                    break

        if not os.path.exists(dump_path):
            print(f"  SKIP {i}: file not created")
            fail_count += 1
            continue

        with open(dump_path, 'rb') as f:
            magic = f.readline().strip()
            if magic != b'P6':
                print(f"  SKIP {i}: bad magic {magic}")
                fail_count += 1
                continue
            line = f.readline().strip()
            while line.startswith(b'#'):
                line = f.readline().strip()
            parts = line.split()
            w = int(parts[0])
            h = int(parts[1])
            maxval = int(f.readline().strip())
            data = f.read(w * h * 3)

        if len(data) < w * h * 3:
            print(f"  SKIP {i}: truncated PPM ({len(data)} < {w*h*3})")
            fail_count += 1
            continue

        flicker = check_flicker(data, w, h, args.bar_h)
        if flicker:
            flicker_count += 1
        else:
            clean_count += 1

        # save first frame always (for debugging)
        if i == 0:
            import shutil
            shutil.copy(dump_path, os.path.join(args.tmpdir, f'captured-{i:03d}.ppm'))

        # on first flicker, dump per-row sample detail
        if flicker and flicker_count == 1:
            try:
                with open(os.path.join(args.tmpdir, 'flicker-debug.txt'), 'w') as dbg:
                    dbg.write("Row  samples(R,G,B)  #clear\n")
                    for row in range(h - args.bar_h, h):
                        row_start = row * w * 3
                        row_data = data[row_start:row_start + w * 3]
                        clear_px = 0
                        samples = []
                        for sx in range(10):
                            px = sx * (w // 10) * 3
                            rgb = (row_data[px], row_data[px+1], row_data[px+2])
                            samples.append(rgb)
                            if rgb == (15, 23, 41):
                                clear_px += 1
                        if clear_px > 0:
                            dbg.write(f"row {row:3d}:  {' '.join(f'({r},{g},{b})' for r,g,b in samples)}  clear={clear_px}\n")
            except Exception as e:
                print(f"  WARN: debug file write failed: {e}")
        os.remove(dump_path)

        time.sleep(args.delay)

    mon.close()
    ser.close()

    total = flicker_count + clean_count
    print()

    # Diagnose the first flicker frame
    diag_path = os.path.join(args.tmpdir, 'first-flicker.ppm')
    if os.path.exists(diag_path):
        with open(diag_path, 'rb') as f:
            f.readline()
            line = f.readline().strip()
            while line.startswith(b'#'):
                line = f.readline().strip()
            dw, dh = map(int, line.split())
            f.readline()
            ddata = f.read(dw * dh * 3)
        # check a few well-known spots
        def px(x, y):
            i = (y * dw + x) * 3
            return (ddata[i], ddata[i+1], ddata[i+2])
        print(f"  Frame diagnostics ({dw}x{dh}):")
        print(f"    center ({dw//2},{dh//2}):      {px(dw//2, dh//2)}")
        print(f"    top-left (10,10):              {px(10,10)}")
        # progress bar region sample
        bar_y = dh - 24  # middle of bar
        print(f"    bar-row ({100},{bar_y}):           {px(100, bar_y)}")
        print(f"    bar-row ({500},{bar_y}):           {px(500, bar_y)}")
        print(f"    bar-row ({900},{bar_y}):           {px(900, bar_y)}")
        # count how many pixels are the clear colour
        clear_rgb = bytes([15, 23, 41])
        clear_count = sum(1 for i in range(0, len(ddata), 3) if ddata[i:i+3] == clear_rgb)
        total_px = dw * dh
        print(f"    clear-colour pixels: {clear_count}/{total_px} ({100*clear_count//total_px}%)")

    print(f"  Clean frames:   {clean_count}/{total}")
    print(f"  Flicker frames: {flicker_count}/{total}")

    if total == 0:
        print("  FAIL: no frames captured")
        sys.exit(1)
    if flicker_count > 0:
        print(f"  FAIL: flicker detected in {flicker_count}/{total} frames")
        sys.exit(1)
    print("  PASS: no flicker detected")
    sys.exit(0)


if __name__ == '__main__':
    main()
