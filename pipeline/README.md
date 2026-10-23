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
| `style.tar.gz` | `roadto_pipeline style` (RoadTo's own style, `drive_style.py`) | style, sprite and fonts, no network |
| `routing.tar` | [Valhalla](https://github.com/valhalla/valhalla) 3.9.1 | offline routing on Android (valhalla-mobile); optional |
| `routing.json` | `roadto_pipeline routing-config` | Valhalla config for that graph, paths filled in by the app; optional |
| `manifest.json` | `roadto_pipeline manifest` | size and SHA-256 of every file |
| `manifest.json.sig` | `roadto_pipeline sign` | Ed25519 signature of the manifest |
| `<id>.roadto` | `roadto_pipeline bundle` | the signed package as one file, to embed or import |

The style is RoadTo's own (`roadto_pipeline/drive_style.py`), made for
driving after Waze: a near-white ground, thick rounded roads coloured by
importance (white streets, yellow main roads, orange fast roads), few
buildings, no points of interest, bold street names. `style-night.json` is
the same with a deep blue ground; the app shows it between sunset and
sunrise (computed from the position, offline), or always or never as set.

Street names run along the roads; during a trip the app switches to the
`*-nav` layers instead, where names sit level in bubbles (the sprite drawn by
`roadto_pipeline/sprites.py`). The empty `roadto-labels` layer marks where
labels begin: the apps draw the route under it, so it never covers a name.
`--style-url` still adapts another OpenMapTiles style (Liberty before), with
`night.py` deriving its night colours.

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

An address is a house number with its street: `addr:street` (or
`addr:place`), or else the name of the `associatedStreet` relation the
number belongs to (role `house`). Many French imports work that way, the
Grand Lyon one among them: without the relations, most of Lyon's numbers
were missing (112 addresses instead of 2,032 around Bellecour and Ainay).

Each place shows its commune: `addr:city` when OSM has it, otherwise the
commune whose boundary (`boundary=administrative`, `admin_level=8`) contains
it, and the nearest city, town or village only where no boundary is known.
The extract keeps boundary relations complete (`-S types=multipolygon,boundary`)
so communes cut by the bbox still have their full outline.

File URLs in the manifest are relative to it, so a package can be served
from any static host. The schema of `places.sqlite` is
[`schema/places.sql`](schema/places.sql).

## Stations file (fuel prices, charging points)

Prices change during the day, the map once a month: they travel in their own
small file, `stations.json.gz`, next to the region package (plan J5). Built
by `roadto_pipeline stations` (`roadto_pipeline/stations.py`) from:

| Data | Source | Kept |
| --- | --- | --- |
| Fuel prices | [prix-carburants](https://www.prix-carburants.gouv.fr/rubrique/opendata/) live feed (`instantane` zip) | per station: each fuel's price and update time (prices older than 30 days dropped), fuels out of stock, 24/7 card machine, motorway |
| Charging points | [base IRVE](https://www.data.gouv.fr/fr/datasets/base-nationale-des-irve-infrastructures-de-recharge-pour-vehicules-electriques/) consolidated by data.gouv.fr | per station: number of points, best power, connector types, free, card payment, open to all, 24/7 |

Both are under the Licence Ouverte 2.0. The file is gzipped JSON (Lyon:
about 60 KB, 220 fuel stations and 1,100 charging stations), byte-for-byte
reproducible, and signed like the manifest (`stations.json.gz.sig`). The app
downloads the whole file for its region, never "around me".

The `Stations` workflow (`.github/workflows/stations.yml`) rebuilds it every
3 hours and publishes it to the release `stations-<id>`; the IRVE base
(~110 MB) is downloaded once a day and cached.

```bash
curl -fsSL -o fuel.zip https://donnees.roulez-eco.fr/opendata/instantane
curl -fsSL -o irve.csv https://www.data.gouv.fr/fr/datasets/r/eb76d20a-8501-400e-b336-d85724de5435
python -m roadto_pipeline stations --region regions/lyon.json --fuel fuel.zip --irve irve.csv --out stations.json.gz
```

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

To try a pipeline change before merging it, run the workflow on the branch
with **publish** unticked: the package is built (and signed) but only kept
as a workflow artifact, and the release that app builds embed is left alone.

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
