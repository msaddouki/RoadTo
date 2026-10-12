"""Single-file region package (``<region>.roadto``).

A plain ustar archive holding the signed manifest and the files the app
needs. Used to embed a region in the app at build time and to install one
from a file (USB, AirDrop, Files) without any server. The app reads it in
place, with the same signature and hash checks as a download.
"""

from __future__ import annotations

import json
import tarfile
from pathlib import Path


def build_bundle(package_dir: Path, out_path: Path, *, include_optional: bool = False) -> list[str]:
    """Writes the bundle and returns the member names, manifest first."""
    manifest_path = package_dir / "manifest.json"
    sig_path = package_dir / "manifest.json.sig"
    if not sig_path.exists():
        raise FileNotFoundError(f"{sig_path} missing: sign the manifest first, the app refuses unsigned packages")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    members = ["manifest.json", "manifest.json.sig"] + [
        f["name"] for f in manifest["files"] if f["required"] or include_optional
    ]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    # ustar only (no pax headers): names are short ASCII and files < 8 GB,
    # which keeps the reader in the app trivial.
    with tarfile.open(out_path, "w", format=tarfile.USTAR_FORMAT) as tar:
        for name in members:
            info = tar.gettarinfo(package_dir / name, arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mtime = 0
            with (package_dir / name).open("rb") as f:
                tar.addfile(info, f)
    return members
