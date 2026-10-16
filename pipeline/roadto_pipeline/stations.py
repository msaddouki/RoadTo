"""Builds the stations file of a region: fuel prices and charging points.

Both come from official open data (Licence Ouverte 2.0) and change far more
often than the map, so they travel in their own small file, separate from
the region package (plan, J5):

- **Fuel**: the government's live price feed (prix-carburants, the
  ``instantane`` zip, refreshed every few minutes). One entry per station,
  with each fuel's price and when the station last updated it, fuels out of
  stock, and whether a card machine runs 24/7. Prices older than
  ``MAX_PRICE_AGE`` are dropped: the station has most likely stopped
  reporting.
- **Charging**: the national IRVE base consolidated by data.gouv.fr (one row
  per charge point), grouped by station: number of points, best power,
  connector types, free or not, card payment, open to all or not, hours.

The app downloads the whole file for its region, never "around me", so
nothing tells where the phone is. The file is gzipped JSON, signed like the
region manifest (``<file>.sig``).
"""

from __future__ import annotations

import csv
import gzip
import io
import json
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.etree import ElementTree
from zoneinfo import ZoneInfo

FORMAT_VERSION = 1

FUEL_FEED_URL = "https://donnees.roulez-eco.fr/opendata/instantane"
IRVE_URL = "https://www.data.gouv.fr/fr/datasets/r/eb76d20a-8501-400e-b336-d85724de5435"

# Feed name -> key used in the file and by the app.
FUELS = {"Gazole": "gazole", "SP95": "sp95", "SP98": "sp98", "E10": "e10", "E85": "e85", "GPLc": "gplc"}
MAX_PRICE_AGE = timedelta(days=30)

# The feed's times are French local time, without an offset.
_PARIS = ZoneInfo("Europe/Paris")

CONNECTORS = {
    "prise_type_2": "type2",
    "prise_type_combo_ccs": "ccs",
    "prise_type_chademo": "chademo",
    "prise_type_ef": "ef",
    "prise_type_autre": "other",
}


def _in_bbox(lon: float, lat: float, bbox: list[float]) -> bool:
    return bbox[0] <= lon <= bbox[2] and bbox[1] <= lat <= bbox[3]


def _feed_xml(data: bytes) -> bytes:
    """The XML document, whether given the zip as served or the XML itself."""
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            name = next(n for n in z.namelist() if n.lower().endswith(".xml"))
            return z.read(name)
    return data


def parse_fuel(data: bytes, bbox: list[float], now: datetime) -> list[dict]:
    """Stations of the fuel price feed inside [bbox] (lon/lat min, lon/lat max)."""
    root = ElementTree.fromstring(_feed_xml(data))
    oldest = now - MAX_PRICE_AGE
    out = []
    for pdv in root.iter("pdv"):
        try:
            # PTV_GEODESIC: degrees times 100 000.
            lat = float(pdv.get("latitude") or "") / 100000
            lon = float(pdv.get("longitude") or "") / 100000
        except ValueError:
            continue
        if not _in_bbox(lon, lat, bbox):
            continue
        prices = {}
        for p in pdv.iter("prix"):
            key = FUELS.get(p.get("nom") or "")
            if key is None:
                continue
            try:
                value = float(p.get("valeur") or "")
                updated = datetime.strptime(p.get("maj") or "", "%Y-%m-%d %H:%M:%S").replace(tzinfo=_PARIS)
            except ValueError:
                continue
            # Older versions of the feed gave thousandths of a euro.
            if value > 100:
                value /= 1000
            if value <= 0 or updated < oldest:
                continue
            prices[key] = {"price": round(value, 3), "updated": updated.isoformat()}
        out_of_stock = sorted(
            {FUELS[r.get("nom")] for r in pdv.iter("rupture") if r.get("nom") in FUELS} - prices.keys()
        )
        if not prices and not out_of_stock:
            continue
        horaires = pdv.find("horaires")
        out.append(
            {
                "id": pdv.get("id"),
                "lat": round(lat, 5),
                "lon": round(lon, 5),
                "address": (pdv.findtext("adresse") or "").strip(),
                "city": (pdv.findtext("ville") or "").strip(),
                "motorway": pdv.get("pop") == "A",
                "card_24_7": horaires is not None and horaires.get("automate-24-24") == "1",
                "prices": prices,
                "out_of_stock": out_of_stock,
            }
        )
    out.sort(key=lambda s: s["id"])
    return out


def _yes(value: str | None) -> bool:
    return (value or "").strip().lower() in {"true", "1", "oui", "yes"}


def _power_kw(value: str | None) -> float:
    try:
        p = float((value or "").replace(",", "."))
    except ValueError:
        return 0.0
    # The schema says kW; some operators publish watts.
    return p / 1000 if p > 1000 else p


def parse_irve(lines: io.TextIOBase, bbox: list[float]) -> list[dict]:
    """Charging stations of the consolidated IRVE file inside [bbox]."""
    stations: dict[str, dict] = {}
    seen_points: set[str] = set()
    for row in csv.DictReader(lines):
        try:
            lon = float(row["consolidated_longitude"])
            lat = float(row["consolidated_latitude"])
        except (KeyError, ValueError):
            continue
        if not _in_bbox(lon, lat, bbox):
            continue
        sid = (row.get("id_station_itinerance") or "").strip()
        pid = (row.get("id_pdc_itinerance") or "").strip()
        if not sid:
            continue
        # The same charge point can come from several published datasets.
        if pid and pid in seen_points:
            continue
        if pid:
            seen_points.add(pid)
        s = stations.get(sid)
        if s is None:
            access = (row.get("condition_acces") or "").lower()
            s = stations[sid] = {
                "id": sid,
                "lat": round(lat, 5),
                "lon": round(lon, 5),
                "name": (row.get("nom_station") or "").strip(),
                "operator": (row.get("nom_enseigne") or row.get("nom_operateur") or "").strip(),
                "address": (row.get("adresse_station") or "").strip(),
                "points": 0,
                "max_kw": 0.0,
                "connectors": set(),
                "free": False,
                "card": False,
                # "Accès libre", sometimes with a broken accent.
                "open_to_all": "libre" in access,
                "always_open": (row.get("horaires") or "").strip() in {"24/7", "Mo-Su 00:00-24:00", "Mo-Su 00:00-00:00"},
            }
        s["points"] += 1
        s["max_kw"] = max(s["max_kw"], _power_kw(row.get("puissance_nominale")))
        s["connectors"] |= {name for col, name in CONNECTORS.items() if _yes(row.get(col))}
        s["free"] = s["free"] or _yes(row.get("gratuit"))
        s["card"] = s["card"] or _yes(row.get("paiement_cb"))
    out = []
    for s in sorted(stations.values(), key=lambda s: s["id"]):
        s["connectors"] = sorted(s["connectors"])
        s["max_kw"] = round(s["max_kw"], 1)
        out.append(s)
    return out


def build(region: dict, fuel_feed: bytes, irve_csv: Path, out: Path, now: datetime | None = None) -> dict:
    """Writes the stations file of [region] to [out] (gzipped JSON); returns counts."""
    now = now or datetime.now(timezone.utc)
    bbox = region["bbox"]
    fuel = parse_fuel(fuel_feed, bbox, now)
    with open(irve_csv, newline="", encoding="utf-8", errors="replace") as f:
        charging = parse_irve(f, bbox)
    doc = {
        "format": FORMAT_VERSION,
        "region": region["id"],
        "generated": now.astimezone(timezone.utc).isoformat(timespec="seconds"),
        "sources": {
            "fuel": {"url": FUEL_FEED_URL, "licence": "Licence Ouverte 2.0", "by": "prix-carburants.gouv.fr"},
            "charging": {"url": IRVE_URL, "licence": "Licence Ouverte 2.0", "by": "data.gouv.fr (base IRVE)"},
        },
        "fuel": fuel,
        "charging": charging,
    }
    body = json.dumps(doc, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    # mtime 0: the same data gives the same bytes, hence the same signature.
    out.write_bytes(gzip.compress(body, mtime=0))
    return {"fuel": len(fuel), "charging": len(charging), "bytes": out.stat().st_size}
