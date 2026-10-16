# Drives replayed in CI

Each `<name>.gpx` here is replayed by `test/replay_test.dart` against the
Valhalla route it followed, `<name>.route.json` (the `/route` response, as
the app received it). A drive passes when the guidance never declares the car
off route, announces every maneuver before it and detects the arrival.

To add a real drive: record the GPX with any logger (a passenger handles the
phone), save the route the app computed for that trip next to it, and run
`dart test test/replay_test.dart` in `packages/roadto_core`.

`synthetic-*` files are not recorded on the road. Their routes are real
Valhalla responses for the Lyon test region (same request as the app); the
traces are simulated by `simulateDrive` (`test/support/traces.dart`) at a speed
fitting the road, with GPS noise, outliers, a stop, and no fix in tunnels.
Regenerate them with `dart run test/support/make_synthetic_drives.dart`.

| Drive | Covers |
| --- | --- |
| bellecour-lafayette | city centre, 2 turns |
| perrache-saint-jean | underpasses under Perrache, a bridge, Vieux Lyon streets |
| part-dieu-confluence | Rhône quays, maneuvers close together |
| terreaux-croix-rousse | the climb, rue Terme tunnel (no fix), 10 m noise |
| vaise-villeurbanne-periph | Périphérique Nord at 70 km/h, ramps |
| confluence-vienne-a7 | 29 km of A7 at 100 km/h |
| part-dieu-aeroport | 29 km: périphérique, A42, A432 |
| saint-jean-tassin | montée de Choulans hairpins, M6 exit |
| bron-saint-priest | suburbs, six roundabouts, 25 maneuvers |
| ecully-dardilly | narrow lanes, three roundabouts |

They replace neither the plan's real 30-minute drive nor real recordings:
those add what a simulation cannot (multipath between buildings, a receiver
that lags behind, real tunnels).
