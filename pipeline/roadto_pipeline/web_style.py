"""RoadTo's style on online tiles, day and night, with its sprite: for the
web site (web/build.mjs) and the app's online map.

Light on purpose (no OSM tooling): ``python -m roadto_pipeline.web_style
--out DIR``.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from . import drive_style, sprites


def write(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name, palette in (("day", drive_style.DAY), ("night", drive_style.NIGHT)):
        style = drive_style.online_style(palette, f"RoadTo {name}")
        (out / f"roadto-{name}.json").write_text(json.dumps(style, ensure_ascii=False, indent=1))
    sprites.write_sprite(out / "sprites", drive_style.BUBBLES)
    print(f"web style -> {out}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True)
    write(Path(parser.parse_args().out))
