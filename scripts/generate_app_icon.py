#!/usr/bin/env python3
"""Generate a 1024x1024 App Icon PNG (no external deps)."""
import struct
import zlib
from pathlib import Path

SIZE = 1024


def png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path: Path, rgba: bytes, w: int, h: int) -> None:
    raw = b"".join(b"\x00" + rgba[y * w * 4 : (y + 1) * w * 4] for y in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", zlib.compress(raw, 9)) + png_chunk(b"IEND", b"")
    path.write_bytes(data)


def lerp(a, b, t):
    return int(a + (b - a) * t)


def main() -> None:
    # Gradient teal -> indigo, with rounded-ish soft square feel and trash/spark glyph
    top = (32, 120, 255)
    bot = (120, 60, 220)
    pixels = bytearray(SIZE * SIZE * 4)

    cx, cy = SIZE // 2, SIZE // 2
    r_outer = 430

    for y in range(SIZE):
        for x in range(SIZE):
            # full-bleed rounded app icon background (Apple masks corners)
            t = y / (SIZE - 1)
            r = lerp(top[0], bot[0], t)
            g = lerp(top[1], bot[1], t)
            b = lerp(top[2], bot[2], t)

            # subtle vignette
            dx = (x - cx) / r_outer
            dy = (y - cy) / r_outer
            dist = (dx * dx + dy * dy) ** 0.5
            if dist > 1.05:
                shade = 0.88
            else:
                shade = 1.0 - 0.12 * max(0.0, dist - 0.55)

            # soft light orb
            orb = max(0.0, 1.0 - ((x - 320) ** 2 + (y - 280) ** 2) ** 0.5 / 380)
            r = min(255, int(r * shade + 40 * orb))
            g = min(255, int(g * shade + 50 * orb))
            b = min(255, int(b * shade + 60 * orb))

            i = (y * SIZE + x) * 4
            pixels[i : i + 4] = bytes((r, g, b, 255))

    # Draw a simple "stack + spark" using filled rectangles (white, semi via blend)
    def fill_rect(x0, y0, x1, y1, color, alpha=1.0):
        x0, x1 = max(0, x0), min(SIZE, x1)
        y0, y1 = max(0, y0), min(SIZE, y1)
        cr, cg, cb = color
        for y in range(y0, y1):
            for x in range(x0, x1):
                i = (y * SIZE + x) * 4
                pixels[i] = int(pixels[i] * (1 - alpha) + cr * alpha)
                pixels[i + 1] = int(pixels[i + 1] * (1 - alpha) + cg * alpha)
                pixels[i + 2] = int(pixels[i + 2] * (1 - alpha) + cb * alpha)

    # back card
    fill_rect(300, 310, 720, 700, (255, 255, 255), 0.22)
    # mid card
    fill_rect(330, 350, 750, 740, (255, 255, 255), 0.35)
    # front card
    fill_rect(360, 390, 780, 780, (255, 255, 255), 0.92)
    # front card accent bar (junk stripe)
    fill_rect(400, 450, 740, 490, (90, 100, 255), 0.85)
    fill_rect(400, 520, 680, 545, (180, 185, 210), 0.9)
    fill_rect(400, 570, 640, 595, (180, 185, 210), 0.75)

    # spark (diamond)
    for k in range(-28, 29):
        fill_rect(760 + k, 300 - abs(k), 762 + k, 302 + abs(k), (255, 230, 120), 0.95)
        fill_rect(760 - abs(k), 300 + k, 762 + abs(k), 302 + k, (255, 230, 120), 0.95)

    out = Path("/var/minis/shared/PhotoJunkCleaner/PhotoJunkCleaner/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    write_png(out, bytes(pixels), SIZE, SIZE)
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
