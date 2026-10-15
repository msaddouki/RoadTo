import base64
import hashlib
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

import pytest

import tarfile

from roadto_pipeline import bundle, manifest, places, routing, signing, style

FIXTURES = Path(__file__).parent / "fixtures"

# RFC 8032, section 7.1, test 1. Public test vector: never use for real signing.
RFC8032_SEED = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
RFC8032_PUBLIC = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
RFC8032_SIG_EMPTY = bytes.fromhex(
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
)


# --- places ---------------------------------------------------------------

@pytest.fixture(scope="module")
def index(tmp_path_factory) -> sqlite3.Connection:
    out = tmp_path_factory.mktemp("places") / "places.sqlite"
    n = places.build(FIXTURES / "lyon_sample.osm", out, region_id="test", osm_timestamp="2026-10-01T00:00:00Z")
    assert n > 0
    return sqlite3.connect(out)


def search(db: sqlite3.Connection, query: str) -> list[tuple]:
    return db.execute(
        "SELECT p.kind, p.name, p.housenumber, p.street, p.city FROM place_fts"
        " JOIN place p ON p.id = place_fts.rowid WHERE place_fts MATCH ? ORDER BY bm25(place_fts)",
        (query,),
    ).fetchall()


def test_settlements_are_indexed(index):
    rows = index.execute("SELECT kind, name FROM place WHERE kind LIKE 'place=%' ORDER BY name").fetchall()
    assert rows == [("place=city", "Lyon"), ("place=city", "Villeurbanne"), ("place=town", "Écully")]


def test_address_gets_nearest_city(index):
    rows = search(index, "12 republique")
    assert ("address", None, "12", "Rue de la République", "Lyon") in rows


def test_city_comes_from_the_commune_boundary(index):
    city = dict(index.execute("SELECT name, city FROM place WHERE name IN ('Gare Part-Dieu', 'Izivia')").fetchall())
    # Closer to Villeurbanne's centre, but inside Lyon (boundary relation).
    assert city["Gare Part-Dieu"] == "Lyon"
    # Inside Villeurbanne (boundary drawn as a closed way).
    assert city["Izivia"] == "Villeurbanne"


def test_city_falls_back_to_nearest_settlement_outside_boundaries(index):
    assert index.execute("SELECT city FROM place WHERE street = 'Chemin des Cerisiers'").fetchone() == ("Écully",)


def test_search_ignores_accents_and_accepts_prefixes(index):
    assert any(r[1] == "Écully" for r in search(index, "ecul*"))
    assert any(r[1] == "Station du Méridien" for r in search(index, "meridien"))


def test_street_segments_are_merged(index):
    streets = index.execute("SELECT name, city FROM place WHERE kind = 'street'").fetchall()
    assert streets == [("Rue de la République", "Lyon")]


def test_poi_keeps_its_own_city_and_skips_benches(index):
    poi = index.execute("SELECT kind, city FROM place WHERE name = 'Station du Méridien'").fetchone()
    assert poi == ("amenity=fuel", "Écully")
    assert index.execute("SELECT count(*) FROM place WHERE name = 'Banc nommé'").fetchone()[0] == 0


def test_driver_places_are_indexed_without_a_name(index):
    rows = index.execute(
        "SELECT kind, name FROM place WHERE kind IN ('amenity=fuel', 'amenity=parking', 'amenity=charging_station')"
        " ORDER BY kind, name"
    ).fetchall()
    assert rows == [
        ("amenity=charging_station", "Izivia"),          # operator as label
        ("amenity=fuel", "Station du Méridien"),
        ("amenity=fuel", "TotalEnergies"),               # brand as label
        ("amenity=parking", None),                       # public, unnamed; the private one is skipped
    ]
    plan = " ".join(r[-1] for r in index.execute(
        "EXPLAIN QUERY PLAN SELECT * FROM place WHERE kind = 'amenity=fuel' AND lat BETWEEN 45 AND 46"))
    assert "place_kind" in plan


def test_building_address_uses_way_centroid(index):
    lat, lon = index.execute("SELECT lat, lon FROM place WHERE street = 'Chemin des Cerisiers'").fetchone()
    assert lat == pytest.approx(45.77015, abs=1e-4)
    assert lon == pytest.approx(4.78015, abs=1e-4)


def test_index_stats(index, tmp_path_factory):
    path = index.execute("PRAGMA database_list").fetchone()[2]
    text = places.index_stats(path, ["Gare Part-Dieu", "Nowhere"])
    assert "without a commune" in text
    assert "| Lyon |" in text
    assert "- Gare Part-Dieu: Lyon" in text
    assert "- Nowhere: not found" in text


def test_meta(index):
    meta = dict(index.execute("SELECT key, value FROM meta").fetchall())
    assert meta["schema_version"] == places.SCHEMA_VERSION
    assert meta["region"] == "test"
    assert meta["osm_timestamp"] == "2026-10-01T00:00:00Z"


# --- style ----------------------------------------------------------------

def test_style_is_rewritten_for_offline_use():
    src = json.loads((FIXTURES / "style_sample.json").read_text())
    out, fonts, sprites = style.rewrite_style(src)

    assert out["sources"] == {
        "openmaptiles": {
            "type": "vector",
            "url": "pmtiles://@ROADTO_REGION_DIR@/map.pmtiles",
            "attribution": "© OpenMapTiles © OpenStreetMap contributors",
        }
    }
    assert [layer["id"] for layer in out["layers"]] == ["background", "water", "road-label", "place-label"]
    assert out["glyphs"] == "@ROADTO_STYLE_DIR@/fonts/{fontstack}/{range}.pbf"
    assert out["sprite"] == "@ROADTO_STYLE_DIR@/sprites/default"
    assert sprites == [("default", "https://tiles.example.org/sprites/ofm")]
    assert fonts == {"Noto Sans Regular": "Noto_Sans_Regular", "Noto Sans Bold": "Noto_Sans_Bold"}
    assert out["layers"][2]["layout"]["text-font"] == ["Noto_Sans_Regular"]
    assert out["layers"][3]["layout"]["text-font"] == [
        "step", ["zoom"], ["literal", ["Noto_Sans_Regular"]], 10, ["literal", ["Noto_Sans_Bold"]],
    ]
    # The source style is left untouched.
    assert src["sources"]["openmaptiles"]["url"] == "https://tiles.example.org/planet"


def test_glyph_ranges_are_limited_to_latin_scripts():
    jobs = style.glyph_jobs({"Noto Sans Regular": "Noto_Sans_Regular"}, "https://x/{fontstack}/{range}.pbf",
                            style.LATIN_GLYPH_STARTS)
    paths = [p for p, _ in jobs]
    assert len(paths) == len(style.LATIN_GLYPH_STARTS) == 9
    assert "fonts/Noto_Sans_Regular/0-255.pbf" in paths          # basic Latin, French accents
    assert "fonts/Noto_Sans_Regular/1024-1279.pbf" in paths      # Cyrillic
    assert "fonts/Noto_Sans_Regular/8192-8447.pbf" in paths      # punctuation, euro sign
    assert not any("19968" in p for p in paths)                  # no CJK
    assert jobs[0][1] == "https://x/Noto%20Sans%20Regular/0-255.pbf"


def test_style_without_vector_source_is_rejected():
    with pytest.raises(ValueError):
        style.rewrite_style({"sources": {}, "layers": []})


# --- manifest -------------------------------------------------------------

REGION = {"id": "test", "name": "Test", "bbox": [4.8, 45.7, 4.9, 45.8], "geofabrik": "x"}


def _package(tmp_path: Path, with_routing: bool = False) -> Path:
    for name in ("style.tar.gz", "places.sqlite", "map.pmtiles") + (("routing.tar",) if with_routing else ()):
        (tmp_path / name).write_bytes(name.encode())
    return tmp_path


def test_manifest_lists_files_with_hashes(tmp_path):
    m = manifest.build_manifest(REGION, _package(tmp_path), version="2026-10-12", osm_timestamp="T",
                                generator={"planetiler": "0.10.2"},
                                created_at=datetime(2026, 10, 12, 8, tzinfo=timezone.utc))
    assert m["region"] == {"id": "test", "name": "Test", "bbox": [4.8, 45.7, 4.9, 45.8]}
    assert m["created_at"] == "2026-10-12T08:00:00Z"
    assert [f["kind"] for f in m["files"]] == ["style", "places", "map"]
    f = m["files"][2]
    assert f["url"] == "map.pmtiles" and f["size"] == len(b"map.pmtiles") and f["required"] is True
    assert f["sha256"] == hashlib.sha256(b"map.pmtiles").hexdigest()
    assert manifest.encode(m) == manifest.encode(json.loads(manifest.encode(m)))


def test_manifest_optional_routing(tmp_path):
    m = manifest.build_manifest(REGION, _package(tmp_path, with_routing=True), version="v")
    assert m["files"][-1] == {**m["files"][-1], "kind": "routing", "required": False}


def test_manifest_requires_map(tmp_path):
    _package(tmp_path)
    (tmp_path / "map.pmtiles").unlink()
    with pytest.raises(FileNotFoundError):
        manifest.build_manifest(REGION, tmp_path, version="v")


# --- signing --------------------------------------------------------------

def test_rfc8032_vector():
    sig, public = signing.sign_local(b"", base64.b64encode(RFC8032_SEED).decode())
    assert base64.b64decode(public) == RFC8032_PUBLIC
    assert base64.b64decode(sig) == RFC8032_SIG_EMPTY


def test_sign_and_verify_roundtrip():
    private, public = signing.generate_key()
    sig, pub2 = signing.sign_local(b"manifest", private)
    assert pub2 == public
    assert signing.verify(b"manifest", sig, public)
    assert not signing.verify(b"manifest!", sig, public)
    assert not signing.verify(b"manifest", sig, signing.generate_key()[1])


def test_sign_without_key_fails(monkeypatch):
    for var in ("ROADTO_SIGNING_KEY", "VAULT_ADDR", "ROADTO_VAULT_TRANSIT_KEY"):
        monkeypatch.delenv(var, raising=False)
    with pytest.raises(signing.SigningError):
        signing.sign(b"x")


# --- bundle ---------------------------------------------------------------

def test_bundle_packs_signed_package_manifest_first(tmp_path):
    (tmp_path / "pkg").mkdir()
    pkg = _package(tmp_path / "pkg", with_routing=True)
    m = manifest.build_manifest(REGION, pkg, version="v")
    (pkg / "manifest.json").write_bytes(manifest.encode(m))
    (pkg / "manifest.json.sig").write_text("sig\n")
    out = tmp_path / "test.roadto"
    names = bundle.build_bundle(pkg, out)
    assert names == ["manifest.json", "manifest.json.sig", "style.tar.gz", "places.sqlite", "map.pmtiles"]
    with tarfile.open(out) as tar:
        assert tar.getnames() == names
        assert all(t.isfile() and t.mtime == 0 for t in tar.getmembers())
        assert tar.extractfile("map.pmtiles").read() == b"map.pmtiles"
    assert "routing.tar" in bundle.build_bundle(pkg, out, include_optional=True)


def test_bundle_refuses_unsigned_package(tmp_path):
    pkg = _package(tmp_path)
    (pkg / "manifest.json").write_bytes(manifest.encode(manifest.build_manifest(REGION, pkg, version="v")))
    with pytest.raises(FileNotFoundError):
        bundle.build_bundle(pkg, tmp_path / "x.roadto")


# --- routing config -------------------------------------------------------

def test_routing_config_points_at_the_region_and_drops_build_paths():
    built = {
        "mjolnir": {
            "tile_dir": "/data/valhalla_tiles",
            "tile_extract": "/data/package/routing.tar",
            "admin": "/data/valhalla_tiles/admins.sqlite",
            "timezone": "/data/valhalla_tiles/timezones.sqlite",
            "traffic_extract": "/data/traffic.tar",
            "max_cache_size": 1000000000,
            "logging": {"type": "std_out"},
        },
        "additional_data": {"elevation": "/data/elevation/"},
        "service_limits": {"auto": {"max_distance": 5000000.0}},
        "loki": {"actions": ["route", "locate"]},
    }
    out = routing.offline_config(built)
    assert out["mjolnir"]["tile_extract"] == "@ROADTO_REGION_DIR@/routing.tar"
    assert out["mjolnir"]["tile_dir"] == ""
    assert out["mjolnir"]["admin"] == out["mjolnir"]["timezone"] == out["mjolnir"]["traffic_extract"] == ""
    assert out["additional_data"]["elevation"] == ""
    assert out["service_limits"] == built["service_limits"]
    assert out["loki"]["actions"] == ["route", "locate"]
    assert built["mjolnir"]["admin"].startswith("/data/"), "input left untouched"
