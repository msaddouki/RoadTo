"""Valhalla configuration shipped with a region (routing.json).

valhalla_build_config writes a complete configuration with the build
machine's paths. The phone needs the same settings with its own paths: the
graph extract becomes ``@ROADTO_REGION_DIR@/routing.tar`` (replaced by the
app at install time with the region folder) and every other data path
(admin and timezone databases, traffic, transit, elevation) is blanked, as
the phone has none of them.
"""

from __future__ import annotations

import json
from pathlib import Path

REGION_DIR = "@ROADTO_REGION_DIR@"
TILE_EXTRACT = f"{REGION_DIR}/routing.tar"


def offline_config(config: dict, build_root: str = "/data/") -> dict:
    """Copy of [config] with build paths rewritten for the phone."""

    def rewrite(value, key: str | None):
        if isinstance(value, dict):
            return {k: rewrite(v, k) for k, v in value.items()}
        if isinstance(value, list):
            return [rewrite(v, key) for v in value]
        if isinstance(value, str) and value.startswith(build_root):
            return TILE_EXTRACT if key == "tile_extract" else ""
        return value

    out = rewrite(config, None)
    mjolnir = out.setdefault("mjolnir", {})
    mjolnir["tile_extract"] = TILE_EXTRACT
    mjolnir["tile_dir"] = ""
    return out


def write_offline_config(src: Path, out: Path) -> None:
    config = json.loads(src.read_text(encoding="utf-8"))
    out.write_text(json.dumps(offline_config(config), indent=1, sort_keys=True) + "\n", encoding="utf-8")
