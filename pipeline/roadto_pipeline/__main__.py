"""Command line entry point: ``python -m roadto_pipeline <command>``."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import bundle, manifest, places, routing, signing, stations, style


def _cmd_places(a: argparse.Namespace) -> None:
    n = places.build(a.osm, a.out, region_id=a.region_id, osm_timestamp=a.osm_timestamp)
    print(f"places: {n} rows -> {a.out}")


def _cmd_places_stats(a: argparse.Namespace) -> None:
    probes = list(a.probe or [])
    if a.region:
        probes += json.loads(Path(a.region).read_text(encoding="utf-8")).get("search_probes", [])
    print(places.index_stats(a.db, probes), end="")


def _cmd_stations(a: argparse.Namespace) -> None:
    region = json.loads(Path(a.region).read_text(encoding="utf-8"))
    counts = stations.build(region, Path(a.fuel).read_bytes(), Path(a.irve), Path(a.out))
    print(f"stations: {counts['fuel']} fuel, {counts['charging']} charging, {counts['bytes']} bytes -> {a.out}")


def _cmd_style(a: argparse.Namespace) -> None:
    stats = style.build_bundle(Path(a.out), a.style_url)
    print(f"style: {stats} -> {a.out}")


def _cmd_manifest(a: argparse.Namespace) -> None:
    region = json.loads(Path(a.region).read_text(encoding="utf-8"))
    generator = dict(kv.split("=", 1) for kv in a.generator)
    m = manifest.build_manifest(region, Path(a.dir), version=a.version,
                                osm_timestamp=a.osm_timestamp, generator=generator)
    out = Path(a.dir) / "manifest.json"
    out.write_bytes(manifest.encode(m))
    print(f"manifest: {len(m['files'])} files -> {out}")


def _cmd_sign(a: argparse.Namespace) -> None:
    path = Path(a.file)
    sig, public = signing.sign(path.read_bytes())
    Path(f"{path}.sig").write_text(sig + "\n", encoding="ascii")
    print(f"signed {path} with public key {public}")


def _cmd_routing_config(a: argparse.Namespace) -> None:
    routing.write_offline_config(Path(a.src), Path(a.out))
    print(f"routing config -> {a.out}")


def _cmd_bundle(a: argparse.Namespace) -> None:
    members = bundle.build_bundle(Path(a.dir), Path(a.out), include_optional=a.include_optional)
    print(f"bundle: {', '.join(members)} -> {a.out}")


def _cmd_verify(a: argparse.Namespace) -> None:
    path = Path(a.file)
    sig = Path(f"{path}.sig").read_text(encoding="ascii").strip()
    if not signing.verify(path.read_bytes(), sig, a.public_key):
        sys.exit(f"INVALID signature for {path}")
    print(f"valid signature for {path}")


def _cmd_keygen(_: argparse.Namespace) -> None:
    private, public = signing.generate_key()
    print("Private key (store it as the REGION_SIGNING_KEY secret, never commit it):")
    print(private)
    print("Public key (add it to trustedRegionKeys in app/lib/config.dart):")
    print(public)


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="roadto_pipeline")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("places", help="build the offline search index")
    s.add_argument("--osm", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--region-id", required=True)
    s.add_argument("--osm-timestamp")
    s.set_defaults(func=_cmd_places)

    s = sub.add_parser("places-stats", help="summarize a built search index (markdown)")
    s.add_argument("--db", required=True)
    s.add_argument("--region", help="region definition; its search_probes are looked up")
    s.add_argument("--probe", action="append", help="exact place name to look up (repeatable)")
    s.set_defaults(func=_cmd_places_stats)

    s = sub.add_parser("stations", help="build the stations file (fuel prices, charging points)")
    s.add_argument("--region", required=True, help="region definition (regions/<id>.json)")
    s.add_argument("--fuel", required=True, help="fuel price feed, the instantane zip or its XML")
    s.add_argument("--irve", required=True, help="consolidated IRVE file (CSV)")
    s.add_argument("--out", required=True, help="stations.json.gz to write")
    s.set_defaults(func=_cmd_stations)

    s = sub.add_parser("style", help="build the offline style bundle")
    s.add_argument("--out", required=True)
    s.add_argument("--style-url", default=style.DEFAULT_STYLE_URL)
    s.set_defaults(func=_cmd_style)

    s = sub.add_parser("manifest", help="write manifest.json for a package directory")
    s.add_argument("--region", required=True, help="region definition (regions/<id>.json)")
    s.add_argument("--dir", required=True)
    s.add_argument("--version", required=True)
    s.add_argument("--osm-timestamp")
    s.add_argument("--generator", action="append", default=[], metavar="TOOL=VERSION")
    s.set_defaults(func=_cmd_manifest)

    s = sub.add_parser("sign", help="sign a file (writes <file>.sig)")
    s.add_argument("--file", required=True)
    s.set_defaults(func=_cmd_sign)

    s = sub.add_parser("routing-config", help="write the Valhalla config shipped with the package")
    s.add_argument("--src", required=True, help="config written by valhalla_build_config")
    s.add_argument("--out", required=True)
    s.set_defaults(func=_cmd_routing_config)

    s = sub.add_parser("bundle", help="pack a signed package into a single .roadto file")
    s.add_argument("--dir", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--include-optional", action="store_true", help="also pack optional files (routing graph)")
    s.set_defaults(func=_cmd_bundle)

    s = sub.add_parser("verify", help="check <file>.sig against a public key")
    s.add_argument("--file", required=True)
    s.add_argument("--public-key", required=True)
    s.set_defaults(func=_cmd_verify)

    s = sub.add_parser("keygen", help="generate an Ed25519 signing key pair")
    s.set_defaults(func=_cmd_keygen)

    a = p.parse_args(argv)
    a.func(a)


if __name__ == "__main__":
    main()
