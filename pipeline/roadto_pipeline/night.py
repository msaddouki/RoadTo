"""Night variant of the offline map style.

Driving at night, a light map dazzles. This derives a dark style from the
day one (OpenFreeMap Liberty) with the same layers, filters and zoom
behaviour, only other colours:

- every colour has its lightness inverted, hue kept (the usual recipe for
  a dark map), then squeezed into a dim range so nothing glares: light
  ground and buildings turn dark, dark labels turn light, white text halos
  turn dark;
- road lines and fills keep their order instead (white roads stay the
  lightest, casings darker), lifted above the dark ground, so roads stand
  out the way they do in the day style;
- map text is lifted into a lighter range than other colours, and labels
  drawn without a halo (road names on white roads) get a dark one, since
  the night roads are no longer white;
- fill patterns, drawn for a light map (pedestrian hatching, wetlands),
  glare at night: road areas become a plain road-grey fill, other
  patterns are toned down;
- saturation is lowered a little everywhere.

Colours inside expressions (``interpolate``, ``match``, ``case``…) are
converted too; any string that does not parse as a colour is left alone.
"""

from __future__ import annotations

import colorsys
import copy
import re

# Lightness ranges, 0..1.
_INVERT = (0.06, 0.86)   # most colours: L -> lo + (hi - lo) * (1 - L)
_ROADS = (0.14, 0.44)    # road lines and fills: L -> lo + (hi - lo) * L
_TEXT = (0.42, 0.92)     # map text: L -> lo + (hi - lo) * (1 - L)
_HALO = "rgba(18,21,25,0.85)"
_PATTERN_OPACITY = 0.3
_SATURATION = 0.75
_ROAD_SATURATION = 0.6   # coloured major roads glare less
_PEDESTRIAN = "rgb(54,57,61)"  # plain fill for hatched road areas, just above the ground

_HEX = re.compile(r"^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
_FUNC = re.compile(r"^(rgba?|hsla?)\(\s*([^)]*)\)$")


def parse_color(value: str) -> tuple[float, float, float, float] | None:
    """(r, g, b, a) in 0..1 for the CSS colour forms map styles use, else None."""
    s = value.strip()
    m = _HEX.match(s)
    if m:
        h = m.group(1)
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
        a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
        return r, g, b, a
    m = _FUNC.match(s.lower())
    if not m:
        return None
    kind, args = m.group(1), [p.strip() for p in re.split(r"[,\s/]+", m.group(2)) if p.strip()]
    try:
        if kind.startswith("rgb") and len(args) in (3, 4):
            def channel(p: str) -> float:
                return float(p[:-1]) / 100 if p.endswith("%") else float(p) / 255
            r, g, b = (channel(p) for p in args[:3])
        elif kind.startswith("hsl") and len(args) in (3, 4):
            hue = float(args[0].removesuffix("deg")) / 360 % 1
            sat, light = (float(p.removesuffix("%")) / 100 for p in args[1:3])
            r, g, b = colorsys.hls_to_rgb(hue, light, sat)
        else:
            return None
        a = float(args[3].removesuffix("%")) / (100 if args[3].endswith("%") else 1) if len(args) == 4 else 1.0
    except ValueError:
        return None
    clamp = lambda x: min(1.0, max(0.0, x))  # noqa: E731
    return clamp(r), clamp(g), clamp(b), clamp(a)


def _format(r: float, g: float, b: float, a: float) -> str:
    rgb = ",".join(str(round(c * 255)) for c in (r, g, b))
    return f"rgb({rgb})" if a >= 0.999 else f"rgba({rgb},{round(a, 3)})"


def night_color(value: str, *, road: bool = False, text: bool = False) -> str:
    rgba = parse_color(value)
    if rgba is None:
        return value
    r, g, b, a = rgba
    hue, light, sat = colorsys.rgb_to_hls(r, g, b)
    lo, hi = _ROADS if road else _TEXT if text else _INVERT
    light = lo + (hi - lo) * (light if road else 1 - light)
    r, g, b = colorsys.hls_to_rgb(hue, light, sat * (_ROAD_SATURATION if road else _SATURATION))
    return _format(r, g, b, a)


def _convert(value, road: bool, text: bool = False):
    if isinstance(value, str):
        return night_color(value, road=road, text=text)
    if isinstance(value, list):
        return [_convert(v, road, text) for v in value]
    if isinstance(value, dict):  # legacy {"stops": [[z, colour]]} functions
        return {k: _convert(v, road, text) for k, v in value.items()}
    return value


def _is_road(layer: dict) -> bool:
    return layer.get("source-layer") == "transportation" and layer.get("type") in ("line", "fill")


def night_style(style: dict) -> dict:
    """The night variant of a (day) style: same layers, night colours."""
    out = copy.deepcopy(style)
    out["name"] = f"{style.get('name', 'RoadTo')} (night)"
    for layer in out.get("layers", []):
        paint = layer.get("paint")
        if not paint:
            continue
        road = _is_road(layer)
        for prop, value in list(paint.items()):
            if prop.endswith("-color"):
                paint[prop] = _convert(value, road, text=prop == "text-color")
        if "fill-pattern" in paint:
            if road:
                del paint["fill-pattern"]
                paint["fill-color"] = _PEDESTRIAN
            else:
                opacity = paint.get("fill-opacity", 1)
                paint["fill-opacity"] = round(opacity * _PATTERN_OPACITY, 3) if isinstance(opacity, (int, float)) else opacity
        if "text-color" in paint and "text-halo-color" not in paint:
            paint["text-halo-color"] = _HALO
            paint.setdefault("text-halo-width", 1)
    return out
