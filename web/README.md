# RoadTo web site

A static companion site for the apps, with nothing to run on a server:

| Page | What it does |
| --- | --- |
| `index.html` | What RoadTo is, the privacy promises, the closed beta |
| `carte.html` | **Live alerts**, read only: the relays' alerts for the area on screen, verified (id, Schnorr signature, proof of work), not expired and trusted enough, as the app shows them |
| `itineraire.html#de=…&vers=…` | **Route preview and guidance**. The preview, like the app's before "Partir": search (Photon), route (Valhalla), time, length, arrival, and the alerts on the way from the relays; roads reported closed or blocked are avoided. "Démarrer" guides like the app's trip screen (below); "Ouvrir dans RoadTo" hands the destination to the app. Both ends are in the fragment; "Ma position" is never put in the link |
| `lieu.html#lat,lon,name` | A **shared place**, with "Ouvrir dans RoadTo" (`roadto://place?…`) and "Itinéraire". The place is in the fragment, which browsers never send to the server |
| `confidentialite.html`, `cgu.html` | The privacy policy and terms, built from `docs/beta/` |

Nothing comes from a third party but the map tiles (OpenFreeMap) and, on the
route page only, the search and routing servers: the public Photon and
Valhalla (FOSSGIS) ones the app falls back to, or your own
(`ROADTO_GEOCODER_URL`, `ROADTO_ROUTING_URL`, also to allow in the Content
Security Policy). The map library, the signature check and the app's font
are bundled at build time: no CDN, no Google Fonts, no analytics.

## Guidance in the browser

`src/guidance.js` is the core's `GuidanceEngine` (same projection, off-route
rule, arrival and announcements), checked against the Dart engine on a
replayed drive (`test/guidance.test.js`). `src/navigation.js` runs it on
the browser's location (`watchPosition`) with:

- the next maneuver, its distance and the turn after it ("Puis"), street
  names in bubbles as in the app;
- the voice (the browser's French speech), switchable, remembered;
- speed and the posted limit (Valhalla `trace_attributes`), red when over;
- the next alert ahead from the relays; a road reported closed or an
  accident ahead reroutes, as does leaving the route (3 fixes off, at most
  every 15 s);
- the screen kept on (Screen Wake Lock), the arrival screen;
- the time to arrival as the app computes it (`src/eta.js`, docs/eta.md):
  the engine's time corrected by the visitor's own pace (learned from
  their trips, in this browser only, never in `?simulation`; "Oublier" on
  the route card), the pace of the last minutes and the jams reported on
  the way, with the engine's alternatives weighed when there are jams.

Browsers stop the location when the page is hidden or the screen locks,
and there is no car screen: the page says to keep it open; the apps are
for real use. To try it at a desk, `itineraire.html?simulation` drives
along the route at 50 km/h (`?simulation=90` for 90).

## Build and try

```sh
cd web
npm ci
npm test            # the alert logic against reference values from the Dart core
npm run build       # -> dist/ (needs Python 3 for the map style)
python3 -m http.server -d dist 8000
```

On `localhost` the live map reads the development relay
(`relay/dev_relay`, `ws://localhost:7777`). Elsewhere, set the relays
(`wss://`) and the beta contact in `dist/config.js` when deploying, or try a
relay with `carte.html?relais=wss://relay.example.org`.

## How it fits

- `src/alerts.js`, `src/geohash.js`, `src/routing.js`, `src/geocoder.js`:
  a port of `packages/roadto_core` (event format, AlertStore, reliability;
  Valhalla request and answer, projection on the route, Photon labels). `test/fixtures/core.json` comes
  from the Dart core (`packages/roadto_core/tool/web_fixtures.dart`), so the
  tests fail if the two drift apart; regenerate it when the rules change.
- The map style is RoadTo's own (`pipeline/roadto_pipeline/drive_style.py`)
  on online tiles (`roadto_pipeline.web_style`), the same as the app's.
- CI builds and tests the site (job "Web site", artifact `roadto-web`).

## Deploying

`render.yaml` deploys the site and a relay on Render
([docs/deploy-render.md](../docs/deploy-render.md)). Any other static host
works too: build with `ROADTO_RELAYS` and `ROADTO_CONTACT` set, or edit
`dist/config.js`.

## Not done yet

- Reporting and confirming alerts from the site (a key and proof of work
  in the browser).
- The public Valhalla and Photon servers are for testing (fair use, no
  guarantee). For the beta, host Valhalla with the regions' graphs
  (`routing.tar` of the region packages) and point `ROADTO_ROUTING_URL` at
  it.
- Hosting: any static host works (the files in `dist/`), as long as it
  serves `.mjs` files as JavaScript (the map's worker). With a domain, the
  apps can open `https://<domain>/lieu.html#…` links directly (Android App
  Links, iOS universal links) and share them.
- The apps do not handle `roadto://place` links yet, nor share places.
