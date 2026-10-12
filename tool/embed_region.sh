#!/usr/bin/env bash
# Copies a signed region package from its GitHub release into the app assets,
# so the build ships the region and installs it on first launch.
#
#   tool/embed_region.sh <region-id> [--with-routing]     (needs GH_TOKEN)
#
# --with-routing also embeds the Valhalla graph and its config (Android,
# which routes on the device). A missing release or routing file only warns:
# the app then builds without it.
set -euo pipefail
REGION=${1:?usage: embed_region.sh <region-id> [--with-routing]}
WITH_ROUTING=${2:-}
DEST="$(cd "$(dirname "$0")/.." && pwd)/app/assets/regions/$REGION"
mkdir -p "$DEST"
if ! gh release download "region-$REGION" --dir "$DEST" --clobber \
    -p manifest.json -p manifest.json.sig -p style.tar.gz -p places.sqlite -p map.pmtiles; then
  echo "::warning::No published package for region $REGION: building without it."
  exit 0
fi
if [[ "$WITH_ROUTING" == "--with-routing" ]]; then
  gh release download "region-$REGION" --dir "$DEST" --clobber -p routing.tar -p routing.json \
    || echo "::warning::No routing files for region $REGION: offline routing unavailable in this build."
fi
echo "Embedded region $REGION:"
ls -lh "$DEST"
