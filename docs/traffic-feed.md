# Traffic from open data (Bison Futé)

Drivers report jams; sensors on the national road network report them too.
RoadTo's traffic robot (`relay/traffic_bot`) reads Bison Futé's open data
every minute and publishes the jams as ordinary RoadTo alerts, so the apps
and the site show them, count them in the time to arrival and weigh the
alternatives around them (docs/eta.md) with nothing more to do.

## Source

[Circulation en temps réel – réseau routier non concédé](https://www.data.gouv.fr/datasets/626113a9e7a3010e25422e7f)
(transport.data.gouv.fr with Bison Futé), Licence Ouverte 2.0, on
`tipi.bison-fute.gouv.fr`:

- `QTV-DIR/refDir.csv`, the stations' referential: each station's stretch
  of road in Lambert-93 and its direction. Its header names one column more
  than the rows hold; rows are read by position. 689 stations in France have
  a position (101 of the 354 around Lyon: N346, A7, A47, A450, A42, M7, A43);
  the others cannot be placed and are skipped.
- `TRAFICOLOR-DIR/<area>/`, per area (TraficLyon, TraficMarius, TraficLille…):
  a DATEX II file every minute with each station's state.

States become levels: `heavy` → Ralenti (25 km/h), `congested` → Bouchon
(10 km/h), `impossible` → À l'arrêt (5 km/h); `freeFlow` and `unknown`
publish nothing.

## Alerts

A station counts as jammed after two readings in a row (two minutes). Its
alert is an ordinary `traffic` alert (ADR 0005) at the middle of the
station's stretch, heading the way traffic goes, with three more tags:

| Tag | Example | Meaning |
| --- | --- | --- |
| `level` | `jam` | slow, jam or stopped (anyone may set it) |
| `length` | `999` | metres of road, up to 3 km from a station |
| `src` | `bison-fute/MY269.D1` | source and station: believed from the robot only |

It lives 10 minutes and is published again every 5 minutes while the jam
lasts, at once when it gets worse or better; each station's newest alert
replaces the previous one in the apps. When traffic flows again the last
alert runs out within 10 minutes. A file older than 10 minutes (a stuck
feed) publishes nothing. Drivers are not asked "toujours là ?" about
sensor alerts. The relays check `level`, `length` and `src`, and do not rate
limit the robot's key.

Only the robot's key is believed for `src`: `TrafficSources.keys` in
roadto_core and `TRAFFIC_SOURCE_KEYS` in `web/src/alerts.js`. Anyone else's
`src` tag is ignored, so nobody can pass a report off as Bison Futé's.

## Running it

The relay image carries it (`/app/roadto-traffic`); `roadto-start.sh` starts
it, and starts it again if it stops, when `ROADTO_TRAFFIC_KEY` holds the
robot's private key (64 hex characters). It publishes on its own relay
(`ROADTO_TRAFFIC_RELAYS`, `ws://127.0.0.1:7777`), which replicates to the
others. `ROADTO_TRAFFIC_FEEDS` picks the areas (`TraficLyon`; comma
separated). Run on one relay only.

On Render (render.yaml), set `ROADTO_TRAFFIC_KEY` in the relay's dashboard.
A free relay sleeps after 15 minutes without visitors and the robot with it:
the Starter plan keeps both awake.

To change the key: generate one, put its public key in both lists above,
ship the apps and the site, then change `ROADTO_TRAFFIC_KEY`.

## Next

- The Métropole de Lyon's own sensors (Criter, the city's streets) need an
  account on data.grandlyon.com; the robot takes another source the same way.
- Travel times and speeds (QTV-DIR) could time the stretches themselves.
