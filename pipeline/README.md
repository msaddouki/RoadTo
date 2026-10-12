# Region pipeline

Builds the offline **region packages** the app downloads: map tiles, search
index, map style and routing graph for one region, listed in a signed
manifest. Regions are defined in `regions/<id>.json`; the first one is
`lyon` (Lyon metropolis and its surroundings, bbox 4.55,45.50 – 5.25,46.05).

## Package contents

| File | Built with | Used by the app |
| --- | --- | --- |
| `map.pmtiles` | [Planetiler](https://github.com/onthegomap/planetiler) 0.10.2, OpenMapTiles schema | offline map (MapLibre `pmtiles://`) |
| `places.sqlite` | `roadto_pipeline places` (pyosmium + SQLite FTS5) | offline address and place search |
| `style.tar.gz` | `roadto_pipeline style` (OpenFreeMap Liberty, rewritten) | style, sprites and fonts, no network |
| `routing.tar` | [Valhalla](https://github.com/valhalla/valhalla) 3.9.1 | offline routing on Android (valhalla-mobile); optional |
| `routing.json` | `roadto_pipeline routing-config` | Valhalla config for that graph, paths filled in by the app; optional |
| `manifest.json` | `roadto_pipeline manifest` | size and SHA-256 of every file |
| `manifest.json.sig` | `roadto_pipeline sign` | Ed25519 signature of the manifest |
| `<id>.roadto` | `roadto_pipeline bundle` | the signed package as one file, to embed or import |

The style bundle only carries the glyph ranges for Latin, Greek and Cyrillic
text plus punctuation and currency symbols (`LATIN_GLYPH_STARTS` in
`roadto_pipeline/style.py`). Shipping every range, CJK included, made the
bundle 59 MB for no benefit in France; a region with other scripts must pass
its own ranges.

The search index holds addresses, streets, settlements and named places.
Places drivers look for by category (fuel, charging, parking, toilets, rest
areas) are indexed even without a name, labelled by brand or operator when
there is one; private ones (`access=private|no`) are left out. An index on
`(kind, lat, lon)` serves category search; it is additive, so older apps
read new packages unchanged.

File URLs in the manifest are relative to it, so a package can be served
from any static host. The schema of `places.sqlite` is
[`schema/places.sql`](schema/places.sql).

## Security model

The app installs a package only if:

1. `manifest.json.sig` is a valid Ed25519 signature of the exact bytes of
   `manifest.json` by one of the keys pinned in `app/lib/config.dart`
   (`Defaults.trustedRegionKeys`);
2. every downloaded file has the size and SHA-256 listed in the manifest.

Files are staged and swapped in only when everything checks out, so a broken
update never replaces a working region. Unchanged files are not downloaded
again on update.

Signing backends (`roadto_pipeline/signing.py`):

- **Vault Transit** (production target): set `VAULT_ADDR`, `VAULT_TOKEN` and
  `ROADTO_VAULT_TRANSIT_KEY` (an `ed25519` transit key). The private key
  never leaves Vault.
- **Local key** (CI secret, development): `ROADTO_SIGNING_KEY`, base64 of the
  32-byte Ed25519 seed.

## Building locally

Requires Docker, `osmium-tool`, `curl` and Python 3.11+.

```bash
pip install -r pipeline/requirements.txt
pipeline/build_region.sh lyon             # output in pipeline/work/lyon/package
SKIP_ROUTING=1 pipeline/build_region.sh lyon   # faster, without the Valhalla graph
```

Downloads (Geofabrik extract, Planetiler's Natural Earth and water polygons)
are cached in `pipeline/work/cache`.

## Publishing and delivery

The **Region packages** workflow (`.github/workflows/region.yml`) builds a
region on demand and on the 1st of every month. When the `REGION_SIGNING_KEY`
secret exists, it signs the package, packs `<id>.roadto` and uploads
everything to the rolling GitHub Release `region-<id>`. Without the secret,
the unsigned package is kept as a workflow artifact for inspection.

The repository is private, so the app never downloads from that release.
The package reaches phones in two ways, with no server:

- **embedded**: the CI app builds run `tool/embed_region.sh lyon`, which
  copies the signed files into `app/assets/regions/lyon/`; the app installs
  them on first launch;
- **imported**: download `lyon.roadto` from the release, copy it to the
  phone and pick it in Réglages > Régions hors ligne > Importer.

Both go through the same signature and hash checks as a download. A package
server (MinIO in the plan) can come later: the app core already downloads
from any static host, data files first and manifest last.

One-time setup:

```bash
PYTHONPATH=pipeline python -m roadto_pipeline keygen
gh secret set REGION_SIGNING_KEY          # paste the private key
# add the public key to Defaults.trustedRegionKeys in app/lib/config.dart
gh workflow run region.yml -f region=lyon
```
Map data © OpenStreetMap contributors, under the ODbL.

## Adding a region

Create `regions/<id>.json` (Geofabrik extract path and bbox), add the region
to `Defaults.regions` in the app, and run the workflow with that id.

## Tests

```bash
PYTHONPATH=pipeline python -m pytest pipeline/tests
```

The tests build a search index from a small hand-made OSM file, check the
style rewriting, the manifest and the signatures (including the RFC 8032
test vector). `packages/roadto_core/test/fixtures/region` holds a package
produced by this pipeline and signed with the RFC 8032 test key; the Dart
tests install it from a local HTTP server, which checks that both sides
agree on the format.
