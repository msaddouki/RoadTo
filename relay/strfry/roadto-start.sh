#!/usr/bin/env bash
# Starts strfry, with its logs filtered, and replicates with the other RoadTo
# relays:
#   PEERS=ws://a:7777,ws://b:7777  other relays (the Helm chart lists every
#                                  replica; SELF_HOST, the pod name, drops
#                                  this one). Builds the router config for
#                                  live replication and reconciles with each
#                                  peer by negentropy every SYNC_INTERVAL_SECONDS.
#   ROUTER / PEER_URL              the same for one peer with a router config
#                                  of your own (docker-compose.yml).
#   REAL_IP_HEADER                 header with the client address behind a
#                                  proxy or an ingress (e.g. x-forwarded-for),
#                                  so the rate limit sees clients, not the proxy.
set -euo pipefail

# Every log line, from strfry and from this script, goes through
# redact_logs.py: strfry logs client addresses on each connection and the
# plan requires relay logs without IP.
exec > >(python3 -u /app/redact_logs.py) 2>&1

if [[ -n "${REAL_IP_HEADER:-}" ]]; then
  if [[ ! "$REAL_IP_HEADER" =~ ^[A-Za-z0-9-]+$ ]]; then
    echo "REAL_IP_HEADER must be a header name" >&2
    exit 64
  fi
  sed -i "s|^\([[:space:]]*realIpHeader[[:space:]]*=[[:space:]]*\).*|\1\"${REAL_IP_HEADER}\"|" /etc/strfry.conf
fi

# The database directory: a volume in Docker Compose and Kubernetes, but
# hosts without a disk (Render's free plan) start without it.
mkdir -p /app/strfry-db

peers=()
if [[ -n "${PEERS:-}" ]]; then
  IFS=',' read -ra listed <<< "$PEERS"
  for url in "${listed[@]}"; do
    url="${url//[[:space:]]/}"
    [[ -z "$url" ]] && continue
    if [[ -n "${SELF_HOST:-}" && ( "$url" == *"//${SELF_HOST}."* || "$url" == *"//${SELF_HOST}:"* ) ]]; then
      continue
    fi
    peers+=("$url")
  done
  if (( ${#peers[@]} )); then
    quoted=$(printf '"%s", ' "${peers[@]}")
    cat > /tmp/roadto-router.conf <<EOF
streams {
    peers {
        dir = "both"
        pluginDown = "/app/roadto-policy-peer"
        urls = [ ${quoted%, } ]
    }
}
EOF
    export ROUTER=/tmp/roadto-router.conf
    echo "replicating with ${#peers[@]} peer relay(s)"
  fi
elif [[ -n "${PEER_URL:-}" ]]; then
  peers=("$PEER_URL")
fi

if (( ${#peers[@]} )); then
  (
    sleep 20
    cd /app
    while true; do
      for peer in "${peers[@]}"; do
        ./strfry sync "$peer" --dir both >/dev/null 2>&1 || echo "sync with a peer failed, retrying later" >&2
      done
      sleep "${SYNC_INTERVAL_SECONDS:-300}"
    done
  ) &
fi

exec /app/strfry.sh
