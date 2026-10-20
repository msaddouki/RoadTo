"""RoadTo's own map style, made for driving, on the OpenMapTiles schema.

Built from a palette rather than adapted from a general-purpose style, after
Waze: a near-white ground, thick rounded roads that read by their importance
at a glance, few buildings, few labels (streets, places, water) and no points
of interest (the app shows its own). During a trip, street names show level
in bubbles. One palette per variant (day, night).

The vector source and the fonts are the ones the offline bundle already
carries (``openmaptiles``, Noto Sans); ``style.py`` turns the paths into the
region's placeholders.
"""

from __future__ import annotations

from dataclasses import dataclass

REGULAR = "Noto_Sans_Regular"
BOLD = "Noto_Sans_Bold"
ITALIC = "Noto_Sans_Italic"


@dataclass(frozen=True)
class Palette:
    background: str
    residential: str
    park: str
    wood: str
    water: str
    water_label: str
    building: str
    building_outline: str
    motorway: str
    motorway_casing: str
    trunk: str
    trunk_casing: str
    primary: str
    primary_casing: str
    secondary: str
    secondary_casing: str
    minor: str
    minor_casing: str
    path: str
    rail: str
    label: str
    label_halo: str
    place_label: str
    tunnel_opacity: float = 0.5
    # Road widths relative to _WIDTHS, and the outline added around them.
    road_scale: float = 1.0
    casing: float = 2.5
    # Buildings from this zoom (above 20: none).
    buildings_from: float = 14
    street_font: str = REGULAR
    street_size: float = 1.0
    # Street names in a bubble (sprites.py), level whatever the map's
    # rotation, as Waze shows them; None: along the road.
    bubble: str | None = None


# Width of a road's fill in pixels at zoom 6, 10, 14, 18 and 20.
_WIDTHS = {
    "motorway": (0.8, 2.0, 7, 22, 40),
    "trunk": (0.6, 1.6, 6, 20, 36),
    "primary": (0.4, 1.2, 5.5, 18, 32),
    "secondary": (0, 0.8, 4.5, 16, 28),
    "tertiary": (0, 0.6, 4, 15, 26),
    "minor": (0, 0, 2.2, 11, 20),
    "service": (0, 0, 1, 6, 11),
}
_STOPS = (6, 10, 14, 18, 20)


def _width(kind: str, extra: float = 0, scale: float = 1.0) -> list:
    out: list = ["interpolate", ["exponential", 1.5], ["zoom"]]
    for z, w in zip(_STOPS, _WIDTHS[kind]):
        out += [z, w * scale + (extra if w > 0 else 0)]
    return out


def _classes(*names: str) -> list:
    return ["match", ["get", "class"], list(names), True, False]


# Road kinds, drawn from the least to the most important so the big ones
# end up on top at crossings.
_ROADS = [
    ("service", ("service", "track"), "minor", 13),
    ("minor", ("minor",), "minor", 12),
    ("tertiary", ("tertiary",), "secondary", 9),
    ("secondary", ("secondary",), "secondary", 8),
    ("primary", ("primary",), "primary", 6),
    ("trunk", ("trunk",), "trunk", 5),
    ("motorway", ("motorway",), "motorway", 4),
]


def _road_layers(p: Palette, brunnel: str) -> list[dict]:
    """Casings then fills for one level (tunnel, ground or bridge)."""
    if brunnel == "ground":
        level = ["!", ["match", ["get", "brunnel"], ["bridge", "tunnel"], True, False]]
    else:
        level = ["==", ["get", "brunnel"], brunnel]
    opacity = p.tunnel_opacity if brunnel == "tunnel" else 1
    casings, fills = [], []
    for kind, classes, colour, minzoom in _ROADS:
        fill = getattr(p, colour)
        casing = getattr(p, f"{colour}_casing")
        flt = ["all", level, _classes(*classes)]
        casings.append(
            {
                "id": f"{brunnel}-{kind}-casing",
                "type": "line",
                "source": "openmaptiles",
                "source-layer": "transportation",
                "minzoom": max(minzoom, 11) if kind in ("minor", "service") else minzoom,
                "filter": flt,
                "layout": {"line-cap": "round", "line-join": "round"},
                "paint": {
                    "line-color": casing,
                    "line-width": _width(kind, p.casing, p.road_scale),
                    "line-opacity": opacity,
                },
            }
        )
        fills.append(
            {
                "id": f"{brunnel}-{kind}",
                "type": "line",
                "source": "openmaptiles",
                "source-layer": "transportation",
                "minzoom": minzoom,
                "filter": flt,
                "layout": {"line-cap": "round", "line-join": "round"},
                "paint": {"line-color": fill, "line-width": _width(kind, 0, p.road_scale), "line-opacity": opacity},
            }
        )
    return casings + fills


# Street name layers only shown during a trip (the app switches them,
# lib/ui/map_screen.dart and car/CarMapRenderer.kt), and the ones shown the
# rest of the time.
NAV_LABEL_SUFFIX = "-nav"

# Empty layer right under the labels: the apps draw the route below it, so
# the route never covers a name.
LABELS_MARKER = "roadto-labels"


def _street_names(p: Palette, halo: dict) -> list[dict]:
    """Main streets named from zoom 13, small ones only close up (16).

    Along the road when browsing the map; during a trip, when the palette has
    a bubble, level in a bubble instead (as Waze does), whatever the map's
    rotation and tilt."""
    layers = []
    for kind, classes, minzoom in (
        ("main", ("tertiary", "secondary", "primary", "trunk"), 13),
        ("minor", ("minor",), 16),
    ):
        base = {
            "type": "symbol",
            "source": "openmaptiles",
            "source-layer": "transportation_name",
            "minzoom": minzoom,
            "filter": _classes(*classes),
        }
        text = {
            "symbol-placement": "line",
            "text-field": ["get", "name"],
            "text-font": [p.street_font],
            "text-size": ["interpolate", ["linear"], ["zoom"], 13, 11 * p.street_size, 18, 14 * p.street_size],
        }
        layers.append(
            {
                "id": f"street-name-{kind}",
                **base,
                "layout": {**text, "text-max-angle": 30, "symbol-spacing": 350},
                "paint": {"text-color": p.label, **halo},
            }
        )
        if p.bubble:
            layers.append(
                {
                    "id": f"street-name-{kind}{NAV_LABEL_SUFFIX}",
                    **base,
                    "layout": {
                        **text,
                        "visibility": "none",
                        "symbol-spacing": 500,
                        "text-rotation-alignment": "viewport",
                        "text-pitch-alignment": "viewport",
                        "text-max-width": 12,
                        "icon-image": p.bubble,
                        "icon-text-fit": "both",
                        "icon-rotation-alignment": "viewport",
                        "icon-pitch-alignment": "viewport",
                        "icon-padding": 4,
                    },
                    "paint": {"text-color": p.label},
                }
            )
    return layers


def drive_style(p: Palette, name: str) -> dict:
    halo = {"text-halo-color": p.label_halo, "text-halo-width": 1.6, "text-halo-blur": 0.5}
    layers: list[dict] = [
        {"id": "background", "type": "background", "paint": {"background-color": p.background}},
        {
            "id": "residential",
            "type": "fill",
            "source": "openmaptiles",
            "source-layer": "landuse",
            "filter": _classes("residential", "suburb", "neighbourhood"),
            "paint": {"fill-color": p.residential},
        },
        {
            "id": "wood",
            "type": "fill",
            "source": "openmaptiles",
            "source-layer": "landcover",
            "filter": _classes("wood", "forest"),
            "paint": {"fill-color": p.wood},
        },
        {
            "id": "grass",
            "type": "fill",
            "source": "openmaptiles",
            "source-layer": "landcover",
            "filter": _classes("grass", "farmland", "wetland"),
            "paint": {"fill-color": p.park, "fill-opacity": 0.35},
        },
        {
            "id": "park",
            "type": "fill",
            "source": "openmaptiles",
            "source-layer": "park",
            # Protected areas can be whole city centres (Lyon's UNESCO site).
            "filter": ["!", _classes("protected_area")],
            "paint": {"fill-color": p.park},
        },
        {
            "id": "water",
            "type": "fill",
            "source": "openmaptiles",
            "source-layer": "water",
            "filter": ["!=", ["get", "brunnel"], "tunnel"],
            "paint": {"fill-color": p.water},
        },
        {
            "id": "waterway",
            "type": "line",
            "source": "openmaptiles",
            "source-layer": "waterway",
            "filter": ["!=", ["get", "brunnel"], "tunnel"],
            "paint": {
                "line-color": p.water,
                "line-width": ["interpolate", ["exponential", 1.4], ["zoom"], 8, 0.5, 14, 2, 18, 6],
            },
        },
        {
            "id": "building",
            "type": "fill",
            "source": "openmaptiles",
            "source-layer": "building",
            "minzoom": min(p.buildings_from, 24),
            "paint": {
                "fill-color": p.building,
                "fill-outline-color": p.building_outline,
                "fill-opacity": ["interpolate", ["linear"], ["zoom"], p.buildings_from, 0, p.buildings_from + 1, 1],
            },
        },
        {
            "id": "path",
            "type": "line",
            "source": "openmaptiles",
            "source-layer": "transportation",
            "minzoom": 16,
            "filter": _classes("path"),
            "paint": {
                "line-color": p.path,
                "line-width": ["interpolate", ["linear"], ["zoom"], 16, 0.8, 20, 2],
                "line-dasharray": [2, 2],
            },
        },
        {
            "id": "rail",
            "type": "line",
            "source": "openmaptiles",
            "source-layer": "transportation",
            "minzoom": 11,
            "filter": ["all", _classes("rail"), ["!=", ["get", "brunnel"], "tunnel"]],
            "paint": {"line-color": p.rail, "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.6, 18, 2.5]},
        },
        *_road_layers(p, "tunnel"),
        *_road_layers(p, "ground"),
        *_road_layers(p, "bridge"),
        {
            "id": LABELS_MARKER,
            "type": "line",
            "source": "openmaptiles",
            "source-layer": "transportation",
            "filter": ["==", ["get", "class"], "__none__"],
            "paint": {"line-opacity": 0},
        },
        {
            "id": "oneway",
            "type": "symbol",
            "source": "openmaptiles",
            "source-layer": "transportation",
            "minzoom": 17,
            "filter": ["all", ["==", ["get", "oneway"], 1], _classes("minor", "tertiary", "secondary")],
            "layout": {
                "symbol-placement": "line",
                "symbol-spacing": 120,
                "text-field": "→",
                "text-font": [REGULAR],
                "text-size": 13,
                "text-keep-upright": False,
            },
            "paint": {"text-color": p.minor_casing},
        },
        {
            "id": "water-name",
            "type": "symbol",
            "source": "openmaptiles",
            "source-layer": "waterway",
            "minzoom": 12,
            "filter": _classes("river", "canal"),
            "layout": {
                "symbol-placement": "line",
                "text-field": ["get", "name"],
                "text-font": [ITALIC],
                "text-size": 13,
                "text-letter-spacing": 0.1,
            },
            "paint": {"text-color": p.water_label, **halo},
        },
        *_street_names(p, halo),
        {
            "id": "road-ref",
            "type": "symbol",
            "source": "openmaptiles",
            "source-layer": "transportation_name",
            "minzoom": 8,
            "filter": ["all", _classes("motorway", "trunk"), ["has", "ref"]],
            "layout": {
                "symbol-placement": "line",
                "symbol-spacing": 400,
                "text-field": ["get", "ref"],
                "text-font": [BOLD],
                "text-size": 11,
                "text-rotation-alignment": "viewport",
            },
            "paint": {"text-color": p.label, **halo},
        },
        *[
            {
                "id": f"place-{kind}",
                "type": "symbol",
                "source": "openmaptiles",
                "source-layer": "place",
                # Districts from zoom 13, neighbourhoods from 14: few names
                # in the overview.
                "minzoom": minzoom,
                "maxzoom": 16,
                "filter": _classes(*classes),
                "layout": {
                    "text-field": ["get", "name"],
                    "text-font": [BOLD],
                    "text-size": 11,
                    "text-transform": "uppercase",
                    "text-letter-spacing": 0.08,
                },
                "paint": {"text-color": p.place_label, **halo},
            }
            for kind, classes, minzoom in (("district", ("suburb", "quarter"), 13), ("neighbourhood", ("neighbourhood",), 14))
        ],
        {
            "id": "place",
            "type": "symbol",
            "source": "openmaptiles",
            "source-layer": "place",
            "maxzoom": 14,
            "filter": _classes("city", "town", "village"),
            "layout": {
                "text-field": ["get", "name"],
                "text-font": [BOLD],
                "text-size": ["interpolate", ["linear"], ["zoom"], 6, 11, 12, 16],
            },
            "paint": {"text-color": p.label, **halo},
        },
    ]
    return {
        "version": 8,
        "name": name,
        "sources": {"openmaptiles": {"type": "vector", "url": "pmtiles://@ROADTO_REGION_DIR@/map.pmtiles"}},
        "glyphs": "@ROADTO_STYLE_DIR@/fonts/{fontstack}/{range}.pbf",
        "sprite": "@ROADTO_STYLE_DIR@/sprites/roadto",
        "layers": layers,
    }


# After Waze: a near-white ground, thick rounded roads with a thin grey
# outline, yellow main roads and bright orange fast roads, sky-blue water,
# almost no buildings, bold street names.
DAY = Palette(
    background="#F2F2EF",
    residential="#EEEEEA",
    park="#C8EBB5",
    wood="#BCE3A6",
    water="#A6D8F7",
    water_label="#2F79B5",
    building="#E4E4DF",
    building_outline="#D9D9D3",
    motorway="#FFA726",
    motorway_casing="#E07B00",
    trunk="#FFC233",
    trunk_casing="#E09A00",
    primary="#FFE16B",
    primary_casing="#E6BE2E",
    secondary="#FFFFFF",
    secondary_casing="#B9BDC3",
    minor="#FFFFFF",
    minor_casing="#C4C7CC",
    path="#C4C7CC",
    rail="#C9CCD1",
    label="#2D3640",
    label_halo="#FFFFFF",
    place_label="#6B7682",
    road_scale=1.45,
    casing=2.0,
    buildings_from=16,
    street_font=BOLD,
    street_size=1.1,
    bubble="bubble-day",
)

# The night side of the same: deep blue ground, blue-grey streets, the
# fast roads still orange.
NIGHT = Palette(
    background="#1D2A3A",
    residential="#202F40",
    park="#1F3A35",
    wood="#1C3631",
    water="#0F4C75",
    water_label="#7CC4F2",
    building="#26364A",
    building_outline="#2C3E54",
    motorway="#F29A2E",
    motorway_casing="#9C5A0E",
    trunk="#E7B23C",
    trunk_casing="#8C6A1C",
    primary="#C9B35A",
    primary_casing="#6E6232",
    secondary="#6F86A3",
    secondary_casing="#3A4C63",
    minor="#4D6382",
    minor_casing="#2E3E53",
    path="#3A4C63",
    rail="#3A4C63",
    label="#E6EEF7",
    label_halo="#1D2A3A",
    place_label="#A7B8CC",
    tunnel_opacity=0.45,
    road_scale=1.45,
    casing=2.0,
    buildings_from=16,
    street_font=BOLD,
    street_size=1.1,
    bubble="bubble-night",
)

# Bubbles of the street names: fill and border, for sprites.write_sprite.
BUBBLES = {
    "bubble-day": ("#FFFFFF", "#C4C7CC"),
    "bubble-night": ("#2C3E54", "#4D6382"),
}


# The same style on OpenFreeMap's online tiles, for the web site and the
# app's online map: the source, the glyph server (real font names) and the
# sprite, which the page resolves against its own address (@ROADTO_SPRITE@).
ONLINE_TILES = "https://tiles.openfreemap.org/planet"
ONLINE_GLYPHS = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"


def online_style(p: Palette, name: str) -> dict:
    import copy
    import json

    style = copy.deepcopy(drive_style(p, name))
    style["sources"]["openmaptiles"] = {"type": "vector", "url": ONLINE_TILES}
    style["glyphs"] = ONLINE_GLYPHS
    style["sprite"] = "@ROADTO_SPRITE@"
    text = json.dumps(style)
    for font in (REGULAR, BOLD, ITALIC):
        text = text.replace(f'"{font}"', json.dumps(font.replace("_", " ")))
    return json.loads(text)
