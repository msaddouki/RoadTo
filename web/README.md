# RoadTo web site

A static companion site for the apps, with nothing to run on a server:

| Page | What it does |
| --- | --- |
| `index.html` | What RoadTo is, the privacy promises, the closed beta |
| `carte.html` | **Live alerts**, read only: the relays' alerts for the area on screen, verified (id, Schnorr signature, proof of work), not expired and trusted enough, as the app shows them |
| `lieu.html#lat,lon,name` | A **shared place**, with "Ouvrir dans RoadTo" (`roadto://place?…`). The place is in the fragment, which browsers never send to the server |
| `confidentialite.html`, `cgu.html` | The privacy policy and terms, built from `docs/beta/` |

Nothing comes from a third party but the map tiles (OpenFreeMap): the map
library, the signature check and the app's font are bundled at build time,
no CDN, no Google Fonts, no analytics.

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

- `src/alerts.js`, `src/geohash.js`: a port of `packages/roadto_core`
  (event format, AlertStore, reliability). `test/fixtures/core.json` comes
  from the Dart core (`packages/roadto_core/tool/web_fixtures.dart`), so the
  tests fail if the two drift apart; regenerate it when the rules change.
- The map style is RoadTo's own (`pipeline/roadto_pipeline/drive_style.py`)
  on online tiles (`roadto_pipeline.web_style`), the same as the app's.
- CI builds and tests the site (job "Web site", artifact `roadto-web`).

## Not done yet

- Hosting: any static host works (the files in `dist/`). With a domain, the
  apps can open `https://<domain>/lieu.html#…` links directly (Android App
  Links, iOS universal links) and share them.
- The apps do not handle `roadto://place` links yet, nor share places.
