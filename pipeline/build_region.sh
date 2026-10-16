#!/usr/bin/env bash
# Builds a region package (map, search index, style, routing graph, signed
# manifest) from OpenStreetMap data.
#
#   pipeline/build_region.sh <region-id> [work-dir]
#
# Requires: docker, osmium-tool, curl, python3 with pipeline/requirements.txt.
# Signs the manifest when ROADTO_SIGNING_KEY or Vault Transit is configured
# (see roadto_pipeline/signing.py); otherwise leaves it unsigned.
#
# Environment:
#   ROADTO_CACHE_DIR   downloads kept between runs (default: pipeline/work/cache)
#   SKIP_ROUTING=1     skip the Valhalla graph (faster local runs)
set -euo pipefail

REGION_ID=${1:?usage: build_region.sh <region-id> [work-dir]}
HERE=$(cd "$(dirname "$0")" && pwd)
REGION_JSON="$HERE/regions/$REGION_ID.json"
WORK=${2:-$HERE/work/$REGION_ID}
CACHE=${ROADTO_CACHE_DIR:-$HERE/work/cache}
OUT="$WORK/package"

PLANETILER_VERSION=0.10.2
VALHALLA_VERSION=3.9.1
PLANETILER_IMAGE=ghcr.io/onthegomap/planetiler:$PLANETILER_VERSION
VALHALLA_IMAGE=ghcr.io/valhalla/valhalla:$VALHALLA_VERSION
DOCKER_USER="$(id -u):$(id -g)"

[[ -f "$REGION_JSON" ]] || { echo "unknown region: $REGION_JSON" >&2; exit 1; }
region_field() { python3 -c "import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(','.join(map(str,v)) if isinstance(v,list) else v)" "$REGION_JSON" "$1"; }
GEOFABRIK=$(region_field geofabrik)
BBOX=$(region_field bbox)

mkdir -p "$WORK" "$OUT" "$CACHE/osm" "$CACHE/planetiler-sources"
export PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}"
step() { echo; echo "==> $*"; }

step "OSM extract: $GEOFABRIK"
SRC="$CACHE/osm/$(basename "$GEOFABRIK")-latest.osm.pbf"
REMOTE_MD5=$(curl -fsSL "https://download.geofabrik.de/$GEOFABRIK-latest.osm.pbf.md5" | cut -d' ' -f1)
if [[ -f "$SRC" && "$(md5sum "$SRC" | cut -d' ' -f1)" == "$REMOTE_MD5" ]]; then
  echo "cached: $SRC"
else
  curl -fSL --retry 3 -o "$SRC.tmp" "https://download.geofabrik.de/$GEOFABRIK-latest.osm.pbf"
  [[ "$(md5sum "$SRC.tmp" | cut -d' ' -f1)" == "$REMOTE_MD5" ]] || { echo "md5 mismatch" >&2; exit 1; }
  mv "$SRC.tmp" "$SRC"
fi
OSM_TIMESTAMP=$(osmium fileinfo -g header.option.osmosis_replication_timestamp "$SRC" 2>/dev/null || true)
echo "OSM data as of: ${OSM_TIMESTAMP:-unknown}"

step "Crop to bbox $BBOX"
# Boundary relations are completed too, so communes cut by the bbox keep their
# full outline (search results get their commune from it).
osmium extract --bbox "$BBOX" --strategy smart -S types=multipolygon,boundary --set-bounds --overwrite \
  -o "$WORK/region.osm.pbf" "$SRC"

step "Map tiles (Planetiler $PLANETILER_VERSION)"
docker run --rm --user "$DOCKER_USER" -e JAVA_TOOL_OPTIONS="-Xmx4g" \
  -v "$WORK:/data" -v "$CACHE/planetiler-sources:/sources" \
  "$PLANETILER_IMAGE" \
  --osm_path=/data/region.osm.pbf --download --download_dir=/sources \
  --bounds="$BBOX" --output=/data/package/map.pmtiles --force

if [[ "${SKIP_ROUTING:-0}" != 1 ]]; then
  step "Routing graph (Valhalla $VALHALLA_VERSION)"
  rm -rf "$WORK/valhalla_tiles" "$OUT/routing.tar"
  mkdir -p "$WORK/valhalla_tiles"
  docker run --rm --user "$DOCKER_USER" -v "$WORK:/data" --entrypoint /bin/bash "$VALHALLA_IMAGE" -c '
    set -euo pipefail
    valhalla_build_config --mjolnir-tile-dir /data/valhalla_tiles \
      --mjolnir-tile-extract /data/package/routing.tar \
      --mjolnir-admin /data/valhalla_tiles/admins.sqlite > /data/valhalla.json
    valhalla_build_admins -c /data/valhalla.json /data/region.osm.pbf
    valhalla_build_tiles -c /data/valhalla.json /data/region.osm.pbf
    valhalla_build_extract -c /data/valhalla.json -v'
  python3 -m roadto_pipeline routing-config --src "$WORK/valhalla.json" --out "$OUT/routing.json"
fi

step "Search index"
python3 -m roadto_pipeline places --osm "$WORK/region.osm.pbf" --out "$OUT/places.sqlite" \
  --region-id "$REGION_ID" ${OSM_TIMESTAMP:+--osm-timestamp "$OSM_TIMESTAMP"}

step "Offline style"
python3 -m roadto_pipeline style --out "$OUT/style.tar.gz"

step "Manifest"
python3 -m roadto_pipeline manifest --region "$REGION_JSON" --dir "$OUT" \
  --version "$(date -u +%Y-%m-%d)" ${OSM_TIMESTAMP:+--osm-timestamp "$OSM_TIMESTAMP"} \
  --generator planetiler=$PLANETILER_VERSION --generator valhalla=$VALHALLA_VERSION \
  --generator style=openfreemap-liberty

if [[ -n "${ROADTO_SIGNING_KEY:-}" || ( -n "${VAULT_ADDR:-}" && -n "${ROADTO_VAULT_TRANSIT_KEY:-}" ) ]]; then
  step "Signature"
  python3 -m roadto_pipeline sign --file "$OUT/manifest.json"
  step "Single-file bundle"
  # Optional files included: Android routes offline with the Valhalla graph.
  python3 -m roadto_pipeline bundle --dir "$OUT" --out "$OUT/$REGION_ID.roadto" --include-optional
else
  echo "WARNING: no signing key configured, manifest left unsigned (the app will refuse it)." >&2
fi

step "Package"
ls -lh "$OUT"
