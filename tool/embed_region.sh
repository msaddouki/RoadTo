#!/usr/bin/env bash
# Copies a signed region package from its GitHub release into the app assets,
# so the build ships the region and installs it on first launch.
#
#   tool/embed_region.sh <region-id>       (needs GH_TOKEN)
#
# A missing release only warns: the app then builds without that region.
set -euo pipefail
REGION=${1:?usage: embed_region.sh <region-id>}
DEST="$(cd "$(dirname "$0")/.." && pwd)/app/assets/regions/$REGION"
mkdir -p "$DEST"
if gh release download "region-$REGION" --dir "$DEST" --clobber \
    -p manifest.json -p manifest.json.sig -p style.tar.gz -p places.sqlite -p map.pmtiles; then
  echo "Embedded region $REGION:"
  ls -lh "$DEST"
else
  echo "::warning::No published package for region $REGION: building without it."
fi
