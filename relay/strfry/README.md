# Production relays (strfry)

RoadTo alerts travel through federated Nostr relays. Production relays run
[strfry](https://github.com/hoytech/strfry) (image `dockurr/strfry` 1.1.3)
with the RoadTo write-policy plugin, which applies **the same rules** as the
dev relay and the app: `checkWritePolicy` from `packages/roadto_core`.

## What the relay accepts

Only RoadTo alerts (kind 4550) and "still there?" answers (kind 4551) with:
- a valid signature and the minimum proof of work (12 and 8 bits);
- an expiry bounded by the alert type (NIP-40). Expired events are dropped by strfry.
- consistent geohash tags, at most 7 characters (about 150 m);
- no free text, and no police alerts while that feature is off.

On top of that, a rate limit applies: 30 events per minute per client
address (`ROADTO_RATE_PER_MINUTE`). The limit is kept in memory only and
the plugin never writes addresses out. Events replicated between our relays
are not rate limited.

## Logs without client addresses

strfry logs every connection with its address (`Connect from <ip>`). The
container sends all its output through `redact_logs.py`, which replaces
IPv4 and IPv6 addresses and the address in connection lines with
`[address]`. CI starts both relays and fails if any address remains in
their logs.

## Layout

| File | Role |
| --- | --- |
| `../strfry_policy/` | the plugin (Dart), its tests and `tool/smoke.dart` |
| `Dockerfile` | strfry image + plugin built with `dart build cli` and the glibc runtime from the Dart image |
| `strfry.conf` | strfry defaults with the RoadTo changes marked `RoadTo` |
| `roadto-start.sh` | starts strfry with its logs filtered; with `PEER_URL`, reconciles with the peer by negentropy every 5 min |
| `redact_logs.py` | removes client addresses from every log line (strfry logs one per connection) |
| `router.conf` | live replication to the peer relay, through the same plugin |
| `docker-compose.yml` | two relays (`7777`, `7778`) replicating each other |

## Running

```bash
cd relay/strfry
docker compose up --build -d
cd ../strfry_policy && dart run tool/smoke.dart ws://localhost:7777 ws://localhost:7778
```

`smoke.dart` publishes an alert to one relay and reads it back from the
other. It also checks that spam and police alerts are refused. CI runs it
on every pull request.

In the app, set both relays in Réglages: `ws://<host>:7777` and
`ws://<host>:7778`. In production, put them behind TLS (`wss://`); set
`relay.realIpHeader` in `strfry.conf` so the rate limit sees client
addresses rather than the proxy's.

## Still to do (milestone J3)

- Helm chart and Argo CD deployment.
- Prometheus metrics.
- Rate-limit evasion by rotating addresses, and abuse reporting, are not
  handled yet.
- Load test with a nostr-sdk generator.
