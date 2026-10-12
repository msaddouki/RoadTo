"""Offline map style bundle (style.tar.gz).

Takes an OpenMapTiles-schema style (OpenFreeMap "liberty" by default) and
makes it work without network:

- the vector source points at the region's PMTiles file;
- other sources (raster relief, etc.) and their layers are dropped;
- sprites and glyphs are downloaded into the bundle;
- font names are rewritten to path-safe ids, so the glyph URLs resolve the
  same whether or not the map engine percent-encodes the font stack.

Paths are written with two placeholders that the app replaces at install
time with ``file://`` URLs of the installed region:

- ``@ROADTO_REGION_DIR@`` (the folder holding ``map.pmtiles``),
- ``@ROADTO_STYLE_DIR@`` (the folder where this bundle is extracted).
"""

from __future__ import annotations

import copy
import io
import json
import re
import tarfile
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DEFAULT_STYLE_URL = "https://tiles.openfreemap.org/styles/liberty"
VECTOR_SOURCE = "openmaptiles"
REGION_DIR = "@ROADTO_REGION_DIR@"
STYLE_DIR = "@ROADTO_STYLE_DIR@"

# Expression operators that may start a `text-font` array (as opposed to a
# plain list of font names).
_EXPRESSION_OPS = {"literal", "step", "match", "case", "coalesce", "interpolate", "get"}


def safe_font_id(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")


def _font_list(value) -> bool:
    return isinstance(value, list) and bool(value) and all(isinstance(v, str) for v in value)


def _safe_fonts(value: list[str], fonts: dict[str, str]) -> list[str]:
    # Glyph servers usually serve one font per stack: keep the first.
    fonts.setdefault(value[0], safe_font_id(value[0]))
    return [fonts[value[0]]]


def _rewrite_font_expr(value, fonts: dict[str, str]):
    """Inside an expression, font lists only appear as ["literal", [...]]."""
    if isinstance(value, list) and len(value) == 2 and value[0] == "literal" and _font_list(value[1]):
        return ["literal", _safe_fonts(value[1], fonts)]
    if isinstance(value, list):
        return [_rewrite_font_expr(v, fonts) for v in value]
    return value


def _rewrite_fonts(value, fonts: dict[str, str]):
    """Replaces font lists in a `text-font` value by a single safe font id."""
    if _font_list(value) and value[0] not in _EXPRESSION_OPS:
        return _safe_fonts(value, fonts)
    return _rewrite_font_expr(value, fonts)


def rewrite_style(style: dict) -> tuple[dict, dict[str, str], list[tuple[str, str]]]:
    """Returns (offline style, {font name: safe id}, [(sprite id, remote url)])."""
    out = copy.deepcopy(style)
    sources = out.get("sources", {})
    if VECTOR_SOURCE not in sources:
        raise ValueError(f"style has no '{VECTOR_SOURCE}' source")
    attribution = sources[VECTOR_SOURCE].get("attribution")
    out["sources"] = {
        VECTOR_SOURCE: {
            "type": "vector",
            "url": f"pmtiles://{REGION_DIR}/map.pmtiles",
            **({"attribution": attribution} if attribution else {}),
        }
    }
    out["layers"] = [
        layer for layer in out.get("layers", [])
        if "source" not in layer or layer["source"] == VECTOR_SOURCE
    ]

    fonts: dict[str, str] = {}
    for layer in out["layers"]:
        layout = layer.get("layout", {})
        if "text-font" in layout:
            layout["text-font"] = _rewrite_fonts(layout["text-font"], fonts)

    sprites: list[tuple[str, str]] = []
    sprite = style.get("sprite")
    if isinstance(sprite, str):
        sprites.append(("default", sprite))
        out["sprite"] = f"{STYLE_DIR}/sprites/default"
    elif isinstance(sprite, list):
        out["sprite"] = []
        for s in sprite:
            sprites.append((s["id"], s["url"]))
            out["sprite"].append({"id": s["id"], "url": f"{STYLE_DIR}/sprites/{s['id']}"})

    out["glyphs"] = f"{STYLE_DIR}/fonts/{{fontstack}}/{{range}}.pbf"
    return out, fonts, sprites


def _get(url: str) -> bytes | None:
    try:
        with urllib.request.urlopen(url, timeout=60) as res:  # noqa: S310 - fixed public URLs
            return res.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def build_bundle(out_path: Path, style_url: str = DEFAULT_STYLE_URL, *, workers: int = 16) -> dict:
    """Downloads the style, its sprites and glyphs, and writes the bundle."""
    style = json.loads(_get(style_url) or b"null")
    if not style:
        raise RuntimeError(f"style not found: {style_url}")
    offline, fonts, sprites = rewrite_style(style)
    glyph_template = style["glyphs"]

    files: dict[str, bytes] = {"style.json": json.dumps(offline, ensure_ascii=False, indent=1).encode()}

    jobs = []
    for sprite_id, url in sprites:
        for suffix in (".json", ".png", "@2x.json", "@2x.png"):
            jobs.append((f"sprites/{sprite_id}{suffix}", url + suffix))
    for name, safe in fonts.items():
        for start in range(0, 65536, 256):
            rng = f"{start}-{start + 255}"
            url = glyph_template.replace("{fontstack}", urllib.parse.quote(name)).replace("{range}", rng)
            jobs.append((f"fonts/{safe}/{rng}.pbf", url))

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for path, data in zip((p for p, _ in jobs), pool.map(lambda j: _get(j[1]), jobs)):
            if data is not None:
                files[path] = data

    missing_sprites = [p for p, _ in jobs if p.startswith("sprites/") and p not in files]
    if missing_sprites:
        raise RuntimeError(f"sprite files not found: {missing_sprites}")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(out_path, "w:gz") as tar:
        for path in sorted(files):
            info = tarfile.TarInfo(path)
            info.size = len(files[path])
            info.mtime = 0  # reproducible archive
            tar.addfile(info, io.BytesIO(files[path]))
    return {"fonts": len(fonts), "glyph_files": sum(p.startswith("fonts/") for p in files), "sprites": len(sprites)}
