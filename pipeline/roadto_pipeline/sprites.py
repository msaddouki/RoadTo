"""RoadTo's own map icons, drawn here: the bubbles that hold street names
(as Waze shows them, level and boxed, rather than along the road).

Written as a MapLibre sprite (``roadto.json``/``roadto.png`` and the ``@2x``
pair) without an imaging library: a few rounded rectangles, antialiased by
coverage, encoded with zlib.
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

# Logical size of a bubble; MapLibre stretches its middle to fit the text.
_W, _H, _R = 32, 24, 10


def _hex(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)


def _rounded_rect_coverage(x: float, y: float, w: float, h: float, r: float) -> float:
    """How much of the pixel centred on (x, y) is inside the shape (0 to 1)."""
    cx = min(max(x, r), w - r)
    cy = min(max(y, r), h - r)
    d = math.hypot(x - cx, y - cy) - r  # signed distance to the edge
    return min(max(0.5 - d, 0.0), 1.0)


def bubble(fill: str, border: str, scale: int) -> tuple[int, int, bytes]:
    """RGBA pixels of one bubble: a 1.5 px border around the fill, and a
    soft shadow below."""
    w, h, r = _W * scale, _H * scale, _R * scale
    pad = 2 * scale  # room for the shadow
    out_w, out_h = w, h + pad
    f, b = _hex(fill), _hex(border)
    rows = bytearray()
    for j in range(out_h):
        rows.append(0)  # PNG filter: none
        for i in range(out_w):
            x, y = i + 0.5, j + 0.5
            outer = _rounded_rect_coverage(x, y, w, h, r)
            inner = _rounded_rect_coverage(x - 1.5 * scale, y - 1.5 * scale, w - 3 * scale, h - 3 * scale, r - 1.5 * scale)
            shadow = _rounded_rect_coverage(x, y - pad, w, h, r) * 0.18
            # Fill over border over shadow.
            a_shadow = shadow * (1 - outer)
            rgb = [b[k] * (outer - inner) + f[k] * inner for k in range(3)]
            a = outer + a_shadow
            if outer > 0:
                rgb = [v / outer for v in rgb]
            else:
                rgb = [0, 0, 0]
            rows += bytes([round(rgb[0]), round(rgb[1]), round(rgb[2]), round(min(a, 1) * 255)])
    return out_w, out_h, bytes(rows)


def _png(width: int, height: int, raw: bytes) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def write_sprite(out_dir: Path, bubbles: dict[str, tuple[str, str]]) -> None:
    """Writes roadto(.json|.png) and roadto@2x(...): one stretchable bubble
    per name, {name: (fill, border)}, stacked vertically."""
    out_dir.mkdir(parents=True, exist_ok=True)
    for scale, suffix in ((1, ""), (2, "@2x")):
        index, raw, width, top = {}, bytearray(), 0, 0
        images = [(name, *bubble(fill, border, scale)) for name, (fill, border) in sorted(bubbles.items())]
        width = max(w for _, w, _, _ in images)
        for name, w, h, pixels in images:
            stride = w * 4 + 1
            for j in range(h):
                row = pixels[j * stride : (j + 1) * stride]
                raw += row + bytes(4 * (width - w))
            r, bh = _R * scale, _H * scale
            index[name] = {
                "x": 0,
                "y": top,
                "width": w,
                "height": h,
                "pixelRatio": scale,
                # Only the straight middle stretches; the text sits inside
                # the rounded ends' padding.
                "stretchX": [[r, w - r]],
                "stretchY": [[r, bh - r]],
                "content": [r - 2 * scale, 3 * scale, w - r + 2 * scale, bh - 3 * scale],
            }
            top += h
        (out_dir / f"roadto{suffix}.png").write_bytes(_png(width, top, bytes(raw)))
        (out_dir / f"roadto{suffix}.json").write_text(json.dumps(index, indent=1))
