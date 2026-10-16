import gzip
import io
import json
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from roadto_pipeline import stations

FIXTURES = Path(__file__).parent / "fixtures"
LYON = {"id": "lyon", "bbox": [4.55, 45.5, 5.25, 46.05]}
NOW = datetime(2026, 10, 16, 8, 0, tzinfo=timezone.utc)


def fuel() -> list[dict]:
    return stations.parse_fuel((FIXTURES / "fuel_sample.xml").read_bytes(), LYON["bbox"], NOW)


def charging() -> list[dict]:
    with open(FIXTURES / "irve_sample.csv", newline="", encoding="utf-8") as f:
        return stations.parse_irve(f, LYON["bbox"])


def test_fuel_keeps_stations_of_the_region_with_a_position():
    assert [s["id"] for s in fuel()] == ["69003001", "69960002"]


def test_fuel_prices_with_their_update_time_in_french_time():
    s = fuel()[0]
    assert (s["lat"], s["lon"]) == (45.7605, 4.859)
    assert s["prices"]["gazole"] == {"price": 1.789, "updated": "2026-10-16T07:30:00+02:00"}
    assert s["prices"]["e10"]["price"] == 1.759
    assert s["card_24_7"] is True
    assert s["motorway"] is False


def test_fuel_drops_stale_prices_and_lists_fuels_out_of_stock():
    s = fuel()[0]
    # SP98 was last priced in August: dropped, and listed out of stock.
    assert "sp98" not in s["prices"]
    assert s["out_of_stock"] == ["e85", "sp98"]


def test_fuel_prices_in_thousandths_and_motorway_stations():
    s = fuel()[1]
    assert s["prices"]["gazole"]["price"] == 1.999
    assert s["motorway"] is True
    assert s["card_24_7"] is False


def test_fuel_feed_is_read_from_the_zip_as_served():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("PrixCarburants_instantane.xml", (FIXTURES / "fuel_sample.xml").read_bytes())
    assert len(stations.parse_fuel(buf.getvalue(), LYON["bbox"], NOW)) == 2


def test_charging_groups_points_by_station_once_each():
    by_id = {s["id"]: s for s in charging()}
    assert sorted(by_id) == ["FRIONE1", "FRIZIV1"]
    ionity = by_id["FRIONE1"]
    # Point P1 is listed twice (two datasets): counted once.
    assert ionity["points"] == 2
    # 150000 is in watts.
    assert ionity["max_kw"] == 350
    assert ionity["connectors"] == ["ccs", "type2"]
    assert ionity["operator"] == "IONITY"
    assert (ionity["free"], ionity["card"], ionity["open_to_all"], ionity["always_open"]) == (False, True, True, True)


def test_charging_reads_any_spelling_of_yes_and_broken_accents():
    s = {s["id"]: s for s in charging()}["FRIZIV1"]
    assert s["connectors"] == ["ef", "type2"]
    assert s["free"] is True
    assert s["open_to_all"] is True
    assert s["always_open"] is False
    # No brand: the operator's name.
    assert s["operator"] == "Izivia"


def test_build_writes_a_reproducible_gzipped_file(tmp_path):
    out = tmp_path / "stations.json.gz"
    counts = stations.build(LYON, (FIXTURES / "fuel_sample.xml").read_bytes(), FIXTURES / "irve_sample.csv", out, NOW)
    assert (counts["fuel"], counts["charging"]) == (2, 2)
    doc = json.loads(gzip.decompress(out.read_bytes()))
    assert doc["format"] == stations.FORMAT_VERSION
    assert doc["region"] == "lyon"
    assert doc["generated"] == "2026-10-16T08:00:00+00:00"
    assert doc["sources"]["fuel"]["licence"] == "Licence Ouverte 2.0"
    first = out.read_bytes()
    stations.build(LYON, (FIXTURES / "fuel_sample.xml").read_bytes(), FIXTURES / "irve_sample.csv", out, NOW)
    assert out.read_bytes() == first
