# ADR 0009 — Offline region packages

- Status: accepted (POC)
- Date: 2026-10-12

## Context

The app must replace a GPS on the test region without network (milestone
J2). Maps and search data are too large to ship inside the app (store size
limits, updates tied to app releases) and users only need their own region.

## Decision

- Data is **downloaded per region** after install, never bundled in the APK
  or IPA. A package holds `map.pmtiles`, `places.sqlite`, `style.tar.gz`,
  `routing.tar` and a `manifest.json` listing their size and SHA-256.
- The manifest is **signed with Ed25519** (detached `manifest.json.sig`). The
  app pins the trusted public keys and refuses anything else. The production
  signing key lives in Vault Transit; CI uses a repository secret meanwhile.
- **Map**: Planetiler builds an OpenMapTiles-schema PMTiles file read
  directly by MapLibre (`pmtiles://file://…`); the OpenFreeMap Liberty style
  is rewritten to point at it, with its sprites and fonts in the package.
  Font names are rewritten to path-safe ids so glyph paths do not depend on
  how the map engine encodes them.
- **Search**: a SQLite FTS5 index (accent-insensitive, prefix queries) of
  addresses, streets, settlements and named places, built with pyosmium.
- **Routing**: the Valhalla graph is built and published now, marked
  optional; the app keeps online routing until valhalla-mobile is integrated.
- **Hosting**: rolling GitHub Releases (`region-<id>`) during the POC, in
  place of the MinIO bucket of the plan. URLs in the manifest are relative,
  so moving hosts only changes the manifest URL in the app.
- **Updates**: monthly rebuild; the app re-downloads only files whose hash
  changed, stages them and swaps the region in atomically.
- The offline style is regenerated with absolute paths at each app start,
  because iOS can move the app's data folder across updates.

## Consequences

- First use needs network (Wi-Fi recommended) to download the region.
- Sizes are not measured yet: spikes A and B will set the size budget per
  region and decide how big a region can be.
- The region folder sits in Application Support; it should be excluded from
  iCloud backup before the beta (it can be downloaded again).
- To verify on devices: MapLibre reading `pmtiles://file://` and `file://`
  glyphs on both platforms (supported by MapLibre Android 13.5 and iOS 6.28,
  the versions used).
