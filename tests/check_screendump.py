#!/usr/bin/env python3
"""Analyse a QEMU PPM screendump for known visual defects.

Usage:
  python3 check_screendump.py <file.ppm>   # check a single dump
  python3 check_screendump.py --live       # boot VM, capture dump, check it
"""

import sys, os, struct, subprocess, time, tempfile

WM = 1024
HM = 768
FONT_W = 8
FONT_H = 16
TEXT_Y0 = 2

BG_R, BG_G, BG_B = 15, 23, 41           # dark blue 0x0f1729 (BGRX)
WHITE_R, WHITE_G, WHITE_B = 255, 255, 255

FAILURES = []

def fail(msg):
    FAILURES.append(msg)

# ----- helpers ---------------------------------------------------------------

def load_ppm(path):
    with open(path, 'rb') as f:
        raw = f.read()
    # PPM header: b"P6\n<W> <H>\n255\n"
    hdr_end = raw.index(b'\n255\n') + 5
    hdr = raw[:hdr_end].decode('ascii', errors='replace')
    lines = hdr.strip().split()
    fmt = lines[0]
    w, h = int(lines[1]), int(lines[2])
    if fmt != 'P6' or w != WM or h != HM:
        raise ValueError(f"Unexpected format: {fmt} {w}x{h} (expect P6 {WM}x{HM})")
    pixels = raw[hdr_end:]
    # return as list-of-rows, each row is list of (r,g,b) tuples
    rows = []
    for y in range(h):
        off = y * w * 3
        row = [(pixels[off + x*3], pixels[off + x*3 + 1], pixels[off + x*3 + 2])
               for x in range(w)]
        rows.append(row)
    return rows

def char_row_y(i):
    return TEXT_Y0 + i * FONT_H

# ----- checks ----------------------------------------------------------------

def check_white_bar(rows):
    """Fail if any row at character-row 10 has >=95 % white pixels."""
    y0, y1 = char_row_y(10), char_row_y(11)
    for y in range(y0, y1):
        if y >= len(rows):
            break
        white = sum(1 for r, g, b in rows[y] if (r, g, b) == (WHITE_R, WHITE_G, WHITE_B))
        if white >= WM * 0.95:
            fail(f"WHITE BAR at y={y}: {white}/{WM} white pixels")

def check_text_present(rows, max_row=7):
    """Fail if fewer than 3 text rows have visible white pixels."""
    rows_with_text = 0
    for i in range(max_row):
        yy = char_row_y(i) + FONT_H // 2
        if yy >= len(rows):
            break
        white = sum(1 for r, g, b in rows[yy] if (r, g, b) == (WHITE_R, WHITE_G, WHITE_B))
        if white > 0:
            rows_with_text += 1
    if rows_with_text < 3:
        fail(f"Too few text rows with content: {rows_with_text}")

def check_background(rows):
    """Fail if background colour is wrong in the 'empty' area (row 40..100)."""
    bad = 0
    for y in range(40, 100):
        for x in (0, WM // 2, WM - 1):
            r, g, b = rows[y][x]
            if (r, g, b) != (BG_R, BG_G, BG_B):
                bad += 1
    if bad > 5:
        fail(f"Background colour: {bad} unexpected pixels in sample area")

def check_progress_bar(rows):
    """Fail if the progress-bar area (bottom 48 rows) has no visible content."""
    y0 = HM - 48
    found = any(
        rows[y][WM // 2] != (BG_R, BG_G, BG_B)
        for y in range(y0, HM)
    )
    if not found:
        fail("Progress bar area is all background (likely missing)")

def check_orbit(rows):
    """Fail if no coloured squares (non-bg, non-white) near centre (y 200..500)."""
    found = 0
    for y in range(200, 500):
        for x in range(400, 600):
            px = rows[y][x]
            if px != (BG_R, BG_G, BG_B) and px != (WHITE_R, WHITE_G, WHITE_B):
                found += 1
                if found > 10:
                    break
        if found > 10:
            break
    if found < 3:
        fail("Orbit squares not detected in centre area")

# ----- main ------------------------------------------------------------------

def run_checks(rows):
    for name, fn in [
        ("white_bar",    check_white_bar),
        ("text_present", check_text_present),
        ("background",   check_background),
        ("progress_bar", check_progress_bar),
        ("orbit",        check_orbit),
    ]:
        try:
            fn(rows)
        except Exception as e:
            fail(f"{name}: exception {e}")

def live_test():
    SER = "/tmp/qemu-vm-serial"
    SCR = "/tmp/qemu-vm-screendump.ppm"
    for p in (SER, SCR):
        try: os.unlink(p)
        except FileNotFoundError: pass

    proc = subprocess.Popen(
        ["qemu-system-x86_64", "-enable-kvm", "-m", "2G", "-nographic",
         "-smp", "2", "-vga", "std",
         "-drive", f"file={os.path.dirname(__file__)}/../build/vm-raw.img,format=raw",
         "-net", "none",
         "-monitor", "tcp:127.0.0.1:4444,server,nowait",
         "-serial", f"file:{SER}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Wait for "Graphics test complete"
    ok = False
    for _ in range(50):  # up to 10 s
        time.sleep(0.2)
        try:
            with open(SER) as f:
                if 'Graphics test complete' in f.read():
                    ok = True
                    break
        except FileNotFoundError:
            pass

    if not ok:
        proc.kill()
        proc.wait()
        print("FAIL: did not see 'Graphics test complete' on serial")
        sys.exit(1)

    time.sleep(0.5)
    # Send screendump via monitor
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    try:
        s.connect(('127.0.0.1', 4444))
        s.sendall(f"screendump {SCR}\n".encode())
        time.sleep(0.3)
    except Exception:
        pass
    finally:
        s.close()

    proc.kill()
    proc.wait()

    return SCR

def main():
    import socket  # noqa: needed only for --live

    if len(sys.argv) == 2 and sys.argv[1] == '--live':
        path = live_test()
    elif len(sys.argv) == 2 and os.path.isfile(sys.argv[1]):
        path = sys.argv[1]
    else:
        print(__doc__)
        sys.exit(1)

    rows = load_ppm(path)
    run_checks(rows)

    if FAILURES:
        print("FAILURES:")
        for f in FAILURES:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print("ALL CHECKS PASSED")
        sys.exit(0)

if __name__ == '__main__':
    main()
