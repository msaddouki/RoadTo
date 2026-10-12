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
  engine runs on its own thread and stays loaded between requests.
- **Online fallback**: when on-device routing fails (destination outside
  the region, no graph), the public Valhalla server is used
  (`FallbackRouter`).
- **iOS keeps online routing** for now. valhalla-mobile ships no prebuilt
  iOS binary; the xcframework must be built from source (vcpkg, Valhalla
  submodules). That build belongs in its own CI job, cached and published
  as a release asset, before iOS can route offline.

## Consequences

- The Android app grows by the native library and, with the embedded
  region, by the Lyon graph (91 MB).
- To measure on devices (spike B): route time (p95) and memory on the
  Lyon graph, and the rerouting delay off route.
- Spike C (guidance) is unaffected: `GuidanceEngine` consumes the same
  `TripRoute` whatever the engine.
