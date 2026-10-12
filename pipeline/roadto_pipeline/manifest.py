"""Region package manifest.

A region package is a set of files next to a ``manifest.json`` that lists
them with their size and SHA-256. File URLs are relative to the manifest, so
the same package can be served from a GitHub Release, MinIO or any static
host. The manifest itself is signed (see ``signing.py``).
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

FORMAT = 1

# Files of a region package, in download order. `required: False` files are
# listed for clients that can use them (offline routing arrives with
# valhalla-mobile) and skipped by the others.
PACKAGE_FILES = [
    {"kind": "style", "name": "style.tar.gz", "required": True},
    {"kind": "places", "name": "places.sqlite", "required": True},
    {"kind": "map", "name": "map.pmtiles", "required": True},
    {"kind": "routing", "name": "routing.tar", "required": False},
]

ATTRIBUTION = "© OpenStreetMap contributors (ODbL) · © OpenMapTiles · Style © OpenFreeMap"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build_manifest(
    region: dict,
    package_dir: Path,
    *,
    version: str,
    osm_timestamp: str | None = None,
    generator: dict[str, str] | None = None,
    created_at: datetime | None = None,
) -> dict:
    files = []
    for spec in PACKAGE_FILES:
        path = package_dir / spec["name"]
        if not path.exists():
            if spec["required"]:
                raise FileNotFoundError(f"missing required package file: {path}")
            continue
        files.append({
            "kind": spec["kind"],
            "name": spec["name"],
            "url": spec["name"],
            "size": path.stat().st_size,
            "sha256": sha256_of(path),
            "required": spec["required"],
        })
    created = (created_at or datetime.now(timezone.utc)).replace(microsecond=0)
    manifest = {
        "format": FORMAT,
        "region": {"id": region["id"], "name": region["name"], "bbox": region["bbox"]},
        "version": version,
        "created_at": created.isoformat().replace("+00:00", "Z"),
        "attribution": ATTRIBUTION,
        "generator": generator or {},
        "files": files,
    }
    if osm_timestamp:
        manifest["osm_timestamp"] = osm_timestamp
    return manifest


def encode(manifest: dict) -> bytes:
    """Stable serialization: the signature covers these exact bytes."""
    return (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
