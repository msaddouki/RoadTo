# Hosting a RoadTo relay

Alerts travel through federated relays: anyone can run one, and the app can
use any relay set in Réglages > Relais. This guide runs one relay on a
server with Docker, behind TLS. For several relays on Kubernetes, see the
Helm chart (`deploy/helm/roadto-relay`).

What the relay does and refuses is in [relay/strfry/README.md](../relay/strfry/README.md):
RoadTo alerts and answers only, valid signature and proof of work, bounded
expiry, positions rounded to about 150 m, no free text, no police alerts, 30
events a minute per client address.

## Requirements

- A Linux server with Docker and Docker Compose, a domain name pointing to
  it, ports 80 and 443 open.
- Small needs: alerts expire within 12 hours, so the database stays small;
  1 vCPU and 1 GB of memory are plenty for a city.
- The relay image: until it is published on a registry, build it from this
  repository (`relay/strfry/Dockerfile`).

## Run it

`compose.yaml` on the server, with Caddy in front for TLS (automatic
Let's Encrypt certificates):

```yaml
services:
  relay:
    image: roadto-relay:latest   # built from relay/strfry/Dockerfile
    environment:
      # Caddy passes the client address: the rate limit must see clients,
      # not the proxy.
      REAL_IP_HEADER: x-forwarded-for
      ROADTO_RATE_PER_MINUTE: "30"
      # Optional: replicate with other RoadTo relays (comma separated).
      # PEERS: wss://relay1.example.org,wss://relay2.example.org
    volumes:
      - relay-db:/app/strfry-db
    ulimits:
      nofile: { soft: 65536, hard: 65536 }
    restart: unless-stopped

  caddy:
    image: caddy:2
    ports: ["80:80", "443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
    restart: unless-stopped

volumes:
  relay-db:
  caddy-data:
```

`Caddyfile`:

```
relay.example.org {
    reverse_proxy relay:7777
    # No access log: it would keep client addresses.
    log {
        output discard
    }
}
```

Then:

```sh
docker build -t roadto-relay:latest -f relay/strfry/Dockerfile .   # in the repository
docker compose up -d
```

Check it from the repository (publishes a test alert and reads it back,
checks that spam and police alerts are refused):

```sh
cd relay/strfry_policy && dart run tool/smoke.dart wss://relay.example.org wss://relay.example.org
```

In the app: Réglages > Relais, one address per line, `wss://relay.example.org`.
Two relays or more are better: alerts still go through when one is down.

## Privacy duties

RoadTo promises users that relays keep no IP address
([privacy policy](beta/politique-de-confidentialite.md)). The relay
container removes addresses from its own logs (`redact_logs.py`); keep it
that way in front of it too: no access log in the proxy, no address in
metrics. A relay sees, for the time of a connection, the address of a phone
and the zones of about 5 km it subscribes to.

## Updating

Rebuild the image from the repository and `docker compose up -d`. Alerts
expire on their own; the database needs no maintenance. Replicated relays
catch up by themselves (live replication, and negentropy every 5 minutes).

## Before the beta

- Publish the relay image on a registry, so hosting does not need the
  repository (which will become private).
- Freeze the event kinds (4550, 4551 are provisional, ADR 0005).
