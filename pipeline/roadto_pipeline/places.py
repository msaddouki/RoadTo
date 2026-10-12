"""Builds the offline search index (places.sqlite) from an OSM extract.

The index holds addresses, named streets, settlements and named points of
interest, with a full-text index (SQLite FTS5) that ignores accents. The
schema lives in ``pipeline/schema/places.sql`` and is read by
``OfflineGeocoder`` in ``packages/roadto_core``.
"""

from __future__ import annotations

import math
import sqlite3
from dataclasses import dataclass
from pathlib import Path

import osmium

SCHEMA_VERSION = "1"
SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schema" / "places.sql"

# Settlements, from most to least important. Used for ranking and to give
# addresses and streets a city when OSM does not carry addr:city.
PLACE_IMPORTANCE = {
    "city": 100,
    "town": 85,
    "village": 70,
    "suburb": 60,
    "quarter": 55,
    "neighbourhood": 50,
    "hamlet": 45,
    "locality": 40,
}
CITY_LEVELS = {"city", "town", "village"}

STREET_IMPORTANCE = 30
POI_IMPORTANCE = 20
ADDRESS_IMPORTANCE = 10

# Keys whose named features are worth finding by name.
POI_KEYS = (
    "amenity",
    "shop",
    "tourism",
    "leisure",
    "office",
    "healthcare",
    "historic",
    "aeroway",
    "railway",
    "public_transport",
    "craft",
)
POI_SKIP = {
    ("amenity", "parking_space"),
    ("amenity", "bench"),
    ("amenity", "waste_basket"),
    ("railway", "rail"),
    ("railway", "abandoned"),
    ("public_transport", "platform"),
}

STREET_HIGHWAYS = {
    "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
    "residential", "living_street", "pedestrian", "service", "road",
    "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
}

# Streets with the same name closer than this are merged into one result.
STREET_MERGE_DEG = 0.01


@dataclass
class Row:
    kind: str
    lat: float
    lon: float
    importance: int
    name: str | None = None
    housenumber: str | None = None
    street: str | None = None
    postcode: str | None = None
    city: str | None = None


def _poi_kind(tags) -> str | None:
    for key in POI_KEYS:
        value = tags.get(key)
        if value and (key, value) not in POI_SKIP:
            return f"{key}={value}"
    return None


class _Collector(osmium.SimpleHandler):
    def __init__(self) -> None:
        super().__init__()
        self.rows: list[Row] = []
        self.streets: dict[tuple[str, int, int], Row] = {}

    def node(self, n) -> None:
        if n.location.valid():
            self._feature(n.tags, n.location.lat, n.location.lon, is_way=False)

    def way(self, w) -> None:
        lats, lons = [], []
        for nd in w.nodes:
            if nd.location.valid():
                lats.append(nd.location.lat)
                lons.append(nd.location.lon)
        if not lats:
            return
        # Mean of the vertices: good enough to centre a result on screen.
        self._feature(w.tags, sum(lats) / len(lats), sum(lons) / len(lons), is_way=True)

    def _feature(self, tags, lat: float, lon: float, *, is_way: bool) -> None:
        name = tags.get("name")
        addr = dict(
            housenumber=tags.get("addr:housenumber"),
            street=tags.get("addr:street") or tags.get("addr:place"),
            postcode=tags.get("addr:postcode"),
            city=tags.get("addr:city"),
        )

        place = tags.get("place")
        if name and place in PLACE_IMPORTANCE:
            self.rows.append(Row(f"place={place}", lat, lon, PLACE_IMPORTANCE[place], name=name,
                                 postcode=addr["postcode"]))
            return

        poi = _poi_kind(tags)
        if name and poi:
            self.rows.append(Row(poi, lat, lon, POI_IMPORTANCE, name=name, **addr))
            return

        if addr["housenumber"] and addr["street"]:
            self.rows.append(Row("address", lat, lon, ADDRESS_IMPORTANCE, **addr))
            return

        if is_way and name and tags.get("highway") in STREET_HIGHWAYS:
            key = (name, round(lat / STREET_MERGE_DEG), round(lon / STREET_MERGE_DEG))
            if key not in self.streets:
                self.streets[key] = Row("street", lat, lon, STREET_IMPORTANCE, name=name, street=name)


class _CityIndex:
    """Nearest city, town or village, on a coarse grid."""

    CELL = 0.05  # degrees, about 5 km

    def __init__(self, rows: list[Row]) -> None:
        self.grid: dict[tuple[int, int], list[Row]] = {}
        for r in rows:
            if r.kind.removeprefix("place=") in CITY_LEVELS:
                self.grid.setdefault(self._cell(r.lat, r.lon), []).append(r)

    def _cell(self, lat: float, lon: float) -> tuple[int, int]:
        return math.floor(lat / self.CELL), math.floor(lon / self.CELL)

    def nearest(self, lat: float, lon: float, max_rings: int = 3) -> str | None:
        cy, cx = self._cell(lat, lon)
        for ring in range(max_rings + 1):
            best, best_d = None, math.inf
            for dy in range(-ring, ring + 1):
                for dx in range(-ring, ring + 1):
                    for r in self.grid.get((cy + dy, cx + dx), ()):
                        # Equirectangular distance; larger places attract a bit more.
                        d = math.hypot(r.lat - lat, (r.lon - lon) * math.cos(math.radians(lat)))
                        d /= 1 + r.importance / 200
                        if d < best_d:
                            best, best_d = r, d
            if best is not None:
                return best.name
        return None


def collect(osm_path: str | Path) -> list[Row]:
    """Reads an OSM file (.osm.pbf or .osm) and returns the rows to index."""
    handler = _Collector()
    handler.apply_file(str(osm_path), locations=True)
    rows = handler.rows + list(handler.streets.values())
    cities = _CityIndex(rows)
    for r in rows:
        if r.city is None and not r.kind.startswith("place="):
            r.city = cities.nearest(r.lat, r.lon)
    return rows


def write_index(rows: list[Row], out_path: str | Path, *, region_id: str, osm_timestamp: str | None = None) -> None:
    out_path = Path(out_path)
    out_path.unlink(missing_ok=True)
    db = sqlite3.connect(out_path)
    try:
        db.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        db.executemany(
            "INSERT INTO place (kind, name, housenumber, street, postcode, city, lat, lon, importance)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (r.kind, r.name, r.housenumber, r.street, r.postcode, r.city,
                 round(r.lat, 6), round(r.lon, 6), r.importance)
                for r in rows
            ],
        )
        db.execute(
            "INSERT INTO place_fts (rowid, name, street, housenumber, city)"
            " SELECT id, name, street, housenumber, city FROM place"
        )
        db.execute("INSERT INTO place_fts (place_fts) VALUES ('optimize')")
        meta = {"schema_version": SCHEMA_VERSION, "region": region_id, "rows": str(len(rows))}
        if osm_timestamp:
            meta["osm_timestamp"] = osm_timestamp
        db.executemany("INSERT INTO meta (key, value) VALUES (?, ?)", meta.items())
        db.commit()
        db.execute("VACUUM")
    finally:
        db.close()


def build(osm_path: str | Path, out_path: str | Path, *, region_id: str, osm_timestamp: str | None = None) -> int:
    rows = collect(osm_path)
    write_index(rows, out_path, region_id=region_id, osm_timestamp=osm_timestamp)
    return len(rows)
