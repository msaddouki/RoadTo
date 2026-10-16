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
- **Delivery, no server during the POC**: the signed package is
  - **embedded in the app**: CI copies it from the rolling GitHub Release
    `region-<id>` (private, CI-only) into the app assets; the app installs
    it on first launch, through the same checks as a download;
  - **importable from a file**: `<id>.roadto` (a plain tar of the signed
    package) can be copied to the phone (USB, AirDrop, Files) and installed
    from Réglages > Régions hors ligne.
- **Later, a package server** (MinIO in the plan) for several regions and
  updates without an app release. Manifest URLs are relative, so the app
  only needs the manifest URL; download support is already in the core.
- **Updates**: monthly rebuild; the app re-downloads only files whose hash
  changed, stages them and swaps the region in atomically.
- The offline style is regenerated with absolute paths at each app start,
  because iOS can move the app's data folder across updates.

## Consequences

- The embedded region makes the app about 100 MB larger (Lyon: map 47 MB,
  search index 54 MB, style 1.3 MB); refreshing it means a new app build
  or importing a newer `.roadto`.
- Measured on the first Lyon build (bbox 55 × 61 km, 3.8 M map features,
  284 k search entries): map 47 MB, search index 54 MB, style 1.3 MB,
  routing graph 91 MB. Spikes A and B still set the size budget per region.
- The region folder sits in Application Support and stays out of cloud
  backups, since it can be reinstalled: on iOS it is marked excluded from
  backup (`BackupExclusion`, AppDelegate.swift); on Android backups are off
  (`allowBackup="false"`) and phone-to-phone transfers skip it
  (`data_extraction_rules.xml`).
- To verify on devices: MapLibre reading `pmtiles://file://` and `file://`
  glyphs on both platforms (supported by MapLibre Android 13.5 and iOS 6.28,
  the versions used).
