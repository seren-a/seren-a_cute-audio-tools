#!/usr/bin/env python3
"""App-Symbol für den Matrix Monitor (nachtvioletter Grund, pastell-pinker
Regenglyphen-Streifen). Reine Standardbibliothek: eigener PNG-Encoder und
ICNS-Zusammenbau. Aufruf: python3 make-icon.py [ziel.icns]"""
import sys, zlib, struct

OUT = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.icns"

def png(w, h, px):
    raw = b"".join(b"\x00" + bytes(min(255, max(0, c)) for c in v)
                  for y in range(h) for v in [px(x, y) for x in range(w)])
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

BG = (0x16, 0x0a, 0x13); RADIUS = 150
COLS = [(0xe5,0xc9,0xf2),(0xd2,0x86,0xb7),(0xf5,0x6e,0x7f),(0x42,0xd9,0xc5),
        (0xe5,0xc9,0xf2),(0xd2,0x86,0xb7),(0xf5,0x86,0x69),(0x42,0xd9,0xc5),(0xe5,0xc9,0xf2)]
HEAD = (0xf6, 0xe7, 0xfa)

def rounded(x, y, S):
    r = RADIUS
    cx = min(max(x, r), S - r); cy = min(max(y, r), S - r)
    corner = (x < r or x > S - r) and (y < r or y > S - r)
    return (40 <= x < S - 40 and 40 <= y < S - 40
            and (((x - cx) ** 2 + (y - cy) ** 2 <= r * r) if corner else True))

def pixel(S):
    cols = []
    for i, n in enumerate([7, 5, 8, 4, 6, 5, 7, 4, 6]):
        cols.append((int(S * (0.10 + 0.10 * i)), n, COLS[i]))
    def f(x, y):
        if not rounded(x, y, S):
            return (0, 0, 0, 0)
        for (cx, n, col) in cols:
            bw = max(6, S // 78); bh = max(8, S // 56); gap = max(5, S // 90)
            top = int(S * 0.13)
            for k in range(n):
                gy = top + k * (bh + gap)
                if cx <= x < cx + bw and gy <= y < gy + bh:
                    frac = (y - top) / max(1, S * 0.55)
                    return (col[0], col[1], col[2], int(255 * (1.0 - 0.85 * frac)))
            hy = top + n * (bh + gap)
            if cx <= x < cx + bw and hy <= y < hy + bh:
                return (HEAD[0], HEAD[1], HEAD[2], 235)
        if (x < 52 or y < 52 or x >= S - 52 or y >= S - 52):
            inb = min(x - 40, y - 40, S - 41 - x, S - 41 - y)
            return (0xe5, 0xc9, 0xf2, int(90 * (1 - inb / 12)))
        return (BG[0], BG[1], BG[2], 255)
    return f

imgs = {sz: png(sz, sz, pixel(sz)) for sz in (128, 256, 512, 1024)}
chunks = b""
for typ, sz in ((b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024)):
    d = imgs[sz]
    chunks += typ + struct.pack(">I", len(d) + 8) + d
icns = b"icns" + struct.pack(">I", len(chunks) + 8) + chunks
open(OUT, "wb").write(icns)
print("AppIcon:", OUT, "-", len(icns), "Bytes")