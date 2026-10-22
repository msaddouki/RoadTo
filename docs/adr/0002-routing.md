# ADR 0002 — Routing: Valhalla, on the device when possible

- Status: accepted (POC)
- Date: 2026-10-12

## Decision

- **Valhalla** computes routes, whatever the platform. The request format
  is identical online and offline (`valhallaRouteRequest`), and the answer
  is parsed in one place (`parseValhallaRoute`).
- **Android routes on the device** with
  [valhalla-mobile](https://github.com/Rallista/valhalla-mobile) 0.6.1 (MIT,
  Valhalla 3.9.0 inside), from Maven Central. The region package carries
  the graph (`routing.tar`, built with Valhalla 3.9.1) and a Valhalla config
  (`routing.json`). The app rewrites the config with its own paths at each
  start.
- The app calls it through a MethodChannel (`org.roadto/valhalla`). The
  engine runs on its own thread and stays loaded between requests. Dart
  sends the same JSON request as to a Valhalla server; valhalla-mobile only
  exposes typed requests, so `MainActivity.kt` maps that JSON onto its
  models with Moshi (renaming `kilometers` to `km` and `exclude_polygons` to
  `avoid_polygons`, the older names the models use) and serializes the
  typed response back to JSON. The config only contributes the graph path;
  the library's defaults cover the rest.
- valhalla-mobile needs Android 8.0 (minSdk 26). Its models must survive
  R8 in release builds (`proguard-rules.pro`).
- **Online fallback**: when on-device routing fails (destination outside
  the region, no graph), the public Valhalla server is used
  (`FallbackRouter`).
- **iOS keeps online routing** for now. valhalla-mobile ships no prebuilt
  iOS binary; the xcframework must be built from source (vcpkg, Valhalla
  submodules). That build belongs in its own CI job, cached and published
  as a release asset, before iOS can route offline.

- **Speed limits** come from the same engine: once a route is computed,
  its shape is sent to Valhalla's `trace_attributes` with
  `shape_match: edge_walk` (exact on a shape Valhalla produced), asking only
  for each edge's `speed_limit` and shape indexes. The answer becomes spans
  of distance along the route (`SpeedLimits`), looked up from the guidance
  position. On Android the raw `trace_attributes` call of valhalla-mobile is
  public, so no model mapping is needed. A route without limits (old
  graph, server error) simply shows no sign.

- **Alternatives and time to arrival**: when jams are reported on a
  route, the engine's alternatives (`alternates`) are weighed with them,
  and the time shown is corrected by the driver's pace and the jams
  (docs/eta.md). On Android those requests use valhalla-mobile's raw call
  (`routeRaw`), since the typed answer drops the alternatives.

## Consequences

- The Android app grows by the native library and, with the embedded
  region, by the Lyon graph (91 MB).
- To measure on devices (spike B): route time (p95) and memory on the
  Lyon graph, and the rerouting delay off route.
- Spike C (guidance) is unaffected: `GuidanceEngine` consumes the same
  `TripRoute` whatever the engine.
