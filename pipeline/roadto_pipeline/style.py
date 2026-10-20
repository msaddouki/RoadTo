"""Offline map style bundle (style.tar.gz).

By default the bundle holds RoadTo's own style (drive_style.py), day and
night, with its sprite (sprites.py) and the Noto Sans glyphs it uses.

``--style-url`` instead takes an OpenMapTiles-schema style (such as
OpenFreeMap "liberty") and makes it work without network:

- the vector source points at the region's PMTiles file;
- other sources (raster relief, etc.) and their layers are dropped;
- sprites and glyphs are downloaded into the bundle;
- font names are rewritten to path-safe ids, so the glyph URLs resolve the
  same whether or not the map engine percent-encodes the font stack;
- a night variant, ``style-night.json``, is added next to ``style.json``.

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
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import drive_style
from .night import night_style
from .sprites import write_sprite

DEFAULT_STYLE_URL = "https://tiles.openfreemap.org/styles/liberty"
# Glyphs of the fonts RoadTo's style uses (OpenFreeMap serves Noto Sans).
GLYPHS_URL = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
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


# Glyph ranges are 256 code points each. A full font is 256 ranges per font
# and most of the weight is CJK; Latin, Greek and Cyrillic plus punctuation
# and currency symbols cover French and its neighbours at a fraction of the
# size. Labels outside these ranges render with missing glyphs: regions with
# other scripts must pass their own starts.
LATIN_GLYPH_STARTS = (
    *range(0x0000, 0x0500, 256),  # Latin, Latin Extended, IPA, Greek, Cyrillic
    0x1E00,  # Latin Extended Additional
    0x1F00,  # Greek Extended
    0x2000,  # General punctuation, super/subscripts, currency
    0x2100,  # Letter-like symbols, number forms, arrows
)


def glyph_jobs(fonts: dict[str, str], template: str, starts: tuple[int, ...]) -> list[tuple[str, str]]:
    """(bundle path, remote URL) for every glyph range of every font."""
    jobs = []
    for name, safe in fonts.items():
        for start in starts:
            rng = f"{start}-{start + 255}"
            url = template.replace("{fontstack}", urllib.parse.quote(name)).replace("{range}", rng)
            jobs.append((f"fonts/{safe}/{rng}.pbf", url))
    return jobs


# Identify ourselves: CDNs commonly reject urllib's default user agent.
USER_AGENT = "RoadTo-pipeline/0.1 (+https://github.com/msaddouki/RoadTo)"


def _get(url: str) -> bytes | None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=60) as res:  # noqa: S310 - fixed public URLs
            return res.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def _download(jobs: list[tuple[str, str]], workers: int) -> dict[str, bytes]:
    files: dict[str, bytes] = {}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for path, data in zip((p for p, _ in jobs), pool.map(lambda j: _get(j[1]), jobs)):
            if data is not None:
                files[path] = data
    return files


def _write_tar(out_path: Path, files: dict[str, bytes]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(out_path, "w:gz") as tar:
        for path in sorted(files):
            info = tarfile.TarInfo(path)
            info.size = len(files[path])
            info.mtime = 0  # reproducible archive
            tar.addfile(info, io.BytesIO(files[path]))


def drive_files() -> dict[str, bytes]:
    """RoadTo's style, day and night, and its sprite, as bundle files."""
    files = {
        "style.json": json.dumps(drive_style.drive_style(drive_style.DAY, "RoadTo"), ensure_ascii=False, indent=1).encode(),
        "style-night.json": json.dumps(
            drive_style.drive_style(drive_style.NIGHT, "RoadTo nuit"), ensure_ascii=False, indent=1
        ).encode(),
    }
    with tempfile.TemporaryDirectory() as tmp:
        write_sprite(Path(tmp), drive_style.BUBBLES)
        for f in sorted(Path(tmp).iterdir()):
            files[f"sprites/{f.name}"] = f.read_bytes()
    return files


def build_bundle(
    out_path: Path,
    style_url: str | None = None,
    *,
    glyph_starts: tuple[int, ...] = LATIN_GLYPH_STARTS,
    workers: int = 16,
) -> dict:
    """Writes the bundle: RoadTo's style, or the style at ``style_url`` made
    offline (its sprites and glyphs downloaded)."""
    if style_url is None:
        files = drive_files()
        fonts = {name.replace("_", " "): name for name in (drive_style.REGULAR, drive_style.BOLD, drive_style.ITALIC)}
        glyphs = _download(glyph_jobs(fonts, GLYPHS_URL, glyph_starts), workers)
        if not glyphs:
            raise RuntimeError("no glyphs downloaded")
        files |= glyphs
        _write_tar(out_path, files)
        return {"fonts": len(fonts), "glyph_files": len(glyphs), "sprites": 1}

    style = json.loads(_get(style_url) or b"null")
    if not style:
        raise RuntimeError(f"style not found: {style_url}")
    offline, fonts, sprites = rewrite_style(style)
    glyph_template = style["glyphs"]

    files = {
        "style.json": json.dumps(offline, ensure_ascii=False, indent=1).encode(),
        # Same layers, night colours (night.py); apps older than it ignore it.
        "style-night.json": json.dumps(night_style(offline), ensure_ascii=False, indent=1).encode(),
    }

    jobs = []
    for sprite_id, url in sprites:
        for suffix in (".json", ".png", "@2x.json", "@2x.png"):
            jobs.append((f"sprites/{sprite_id}{suffix}", url + suffix))
    jobs += glyph_jobs(fonts, glyph_template, glyph_starts)
    files |= _download(jobs, workers)

    missing_sprites = [p for p, _ in jobs if p.startswith("sprites/") and p not in files]
    if missing_sprites:
        raise RuntimeError(f"sprite files not found: {missing_sprites}")

    _write_tar(out_path, files)
    return {"fonts": len(fonts), "glyph_files": sum(p.startswith("fonts/") for p in files), "sprites": len(sprites)}
