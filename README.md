# RoadTo

Community navigation and road alerts, with no account and no tracking.
A single Flutter app for **Android and iOS**; alerts travel over federated
Nostr relays and expire on their own; maps and address search work offline
once a region is downloaded.

> Status: **working POC** (milestone J0 and part of J1–J2 of the development
> plan). Routing still uses a public online server; everything else can run
> offline for the Lyon test region.

## What the POC does

- MapLibre map, night theme. **Offline** with a downloaded region package
  (PMTiles + bundled style, sprites and fonts); online OpenFreeMap tiles
  otherwise.
- Address and place search, **offline** in the installed region (SQLite
  FTS5, accent-insensitive), online (Photon) as a fallback. Long-press on the
  map to pick a destination.
- **Search by category** (fuel, charging, parking, rest areas, toilets,
  food), offline: nearest around you, or next ones ahead on the route with
  the distance to them and how far they are from the road.
- Route from Valhalla, turn-by-turn guidance with French voice prompts,
  arrival time, rerouting when off route. **Offline on Android** with the
  region's graph (valhalla-mobile); online on iOS and outside the region.
- **Speed limits** from OSM on the navigation screen, red when over the
  limit (5 km/h margin, 5 % above 100 km/h); from the region's graph on
  Android, from the routing server otherwise.
- **Simulated driving** on by default: the trip is replayed along the route,
  so everything can be tested without driving.
- **One-gesture reporting**: six large tiles, 5 s to cancel. The police
  type stays disabled until the L130-11 channel exists.
- Live alerts from the relays, shown on the map and announced when they lie
  on the route ("Accident dans 800 m").
- **"Still there?"** when passing an alert: yes or no, and its reliability is
  recomputed. A closed road reported ahead triggers a reroute around it.
- Identity generated on the phone (Keystore or Keychain) with a 12-word
  **recovery phrase** (BIP-39, NIP-06) to restore it on another phone, or a
  **password-encrypted backup** file (NIP-49, `ncryptsec`); a throwaway key
  per trip signs the alerts.
- **Error reports stay on the phone** (Réglages > Rapports d’erreur), with
  positions, keys and network addresses removed. Nothing is sent: the user
  can read a report and share it, as a file or by copying it, if they want.

## Repository layout

```
app/                    Flutter app (Android + iOS)
packages/roadto_core/   Pure Dart core: geo, geohash, Nostr, alerts, guidance,
                        simulation, offline regions and search
relay/dev_relay/        Development Nostr relay enforcing the RoadTo write policy
relay/strfry/           Production relays: strfry + the same policy as a plugin
relay/strfry_policy/    The strfry write-policy plugin (Dart) and an end-to-end check
pipeline/               Builds signed offline region packages from OpenStreetMap
docs/adr/               Architecture decision records
docs/poc.md             Running and testing the POC
tool/                   CI scripts
```

## Quick start

```bash
# 1. Dev relay (in a terminal)
cd relay/dev_relay && dart pub get && dart run bin/dev_relay.dart

# 2. App, on an Android emulator or iOS simulator
cd app && flutter pub get && flutter run
```

Details, the two-phone test and limitations: [docs/poc.md](docs/poc.md).
Offline region packages: [pipeline/README.md](pipeline/README.md).

## Tests

```bash
cd packages/roadto_core && dart test   # geo, Nostr, alerts, policy, guidance and GPX replay, regions, offline search
cd relay/dev_relay && dart test        # end to end: publish, receive in < 5 s, expiry, rate limit
cd app && flutter test                 # report sheet, map layers
PYTHONPATH=pipeline python -m pytest pipeline/tests   # region pipeline
```

Guidance is replayed over ten reference drives of a Lyon route (GPS noise,
outliers, a tunnel, a red light, 0.5 to 2 s fixes, 12 to 70 km/h): none may
declare a false off-route, miss an announcement or the arrival. Real drives
recorded on the road go in `packages/roadto_core/test/fixtures/gpx/` with
their route and are replayed the same way.

CI also builds the Android APK and the iOS app (simulator) on every pull
request; both can be downloaded from the workflow artifacts.

## Safety rule

Road tests **always with a passenger** handling the phone. Holding a phone
while driving is illegal in France (art. R412-6-1 of the Code de la route).
Everything goes through simulation first.
