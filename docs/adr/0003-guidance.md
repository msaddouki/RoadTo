# ADR 0003 — Guidance: in-house Dart engine

- Status: accepted (POC), to review with spike C
- Date: 2026-10-16

## Context

Guidance turns a route and a stream of positions into what the driver
sees and hears: the next maneuver and its distance, the time left, voice
prompts, leaving the route, arriving. The plan named Ferrostar for it.
Ferrostar is a Rust core with Kotlin and Swift bindings and has no Flutter
binding, while the app is one Flutter app with a pure Dart core (ADR 0004).

## Decision

- Guidance is **`GuidanceEngine` in `roadto_core`**, pure Dart, the same on
  Android and iOS, fed by the app with each fix. It consumes `TripRoute`,
  whatever engine computed the route (ADR 0002), and reads Valhalla's own
  maneuvers and French verbal instructions.
- **Progress along the route**: each fix is projected on the route,
  looking first where the car can be since its last position (up to 5 s at
  its speed), and never behind it. Nearby parts of the route (underpasses,
  ramps, parallel roads) cannot make the guidance skip or rewind.
- **Off route**: more than 40 m from the route for 3 fixes in a row. The
  app then reroutes from the car's position and heading.
- **Voice prompts**, spoken by the platform's text-to-speech in French:
  - departure;
  - an early prompt between 600 m and the close one ("Dans 500 mètres,
    tournez à droite");
  - a close prompt about 8 s before the maneuver (60 to 250 m);
  - the arrival, once, within 25 m.

  Each prompt is said once. When two maneuvers are close, Valhalla's
  multi-cue phrase announces both.
- **Tested by replay**: recorded or simulated GPS traces are replayed in CI
  (`replayTrace`). A drive passes when the car is never declared off route,
  every maneuver is announced before it and the arrival is detected
  (`packages/roadto_core/test/fixtures/gpx`, ten drives on the Lyon region).

## Alternatives

- **Ferrostar through native plugins**: one Kotlin and one Swift
  integration to maintain, state crossing the platform channel on every
  fix, and a young API (the plan's risk table already lists its churn).
  It would bring map matching, lane guidance and spoken-instruction timing
  that the in-house engine does not have.

## Consequences

- No lane guidance and no map matching beyond the projection on the
  route: to reconsider if real drives show the need.
- Changes to guidance are plain Dart, covered by unit tests and replays
  without a device.
- The car screens (J4, J8) need the guidance state on the native side:
  the engine's state is sent to the car app rather than computed twice.
- To review after real drives (spike C, and the plan's 30-minute drive in
  airplane mode): rerouting delay, prompts at motorway speed, behaviour in
  long tunnels. Ferrostar stays the fallback if these fall short.
