#!/usr/bin/env bash
# Starts strfry (with its router when ROUTER points to a config file) and, when
# PEER_URL is set, reconciles with the peer relay every SYNC_INTERVAL_SECONDS
# using negentropy, so a relay that was down catches up.
set -euo pipefail

if [[ -n "${PEER_URL:-}" ]]; then
  (
    sleep 20
    cd /app
    while true; do
      ./strfry sync "$PEER_URL" --dir both >/dev/null 2>&1 || echo "sync with peer failed, retrying later" >&2
      sleep "${SYNC_INTERVAL_SECONDS:-300}"
    done
  ) &
fi

exec /app/strfry.sh
