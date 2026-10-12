# Running and testing the POC

## Prerequisites

- Flutter 3.47 (stable): <https://docs.flutter.dev/get-started/install>
- Android: Android Studio (JDK 21, required by MapLibre) and an emulator, or a
  phone in developer mode.
- iOS: a Mac with Xcode (simulator or iPhone).

Without a mobile dev machine, every pull request produces in GitHub Actions:

- `roadto-android-apk`: APK to install on an Android phone;
- `roadto-ios-simulator`: app for the iOS simulator on a Mac
  (`xcrun simctl install booted Runner.app`).

## 1. The dev relay

```bash
cd relay/dev_relay
dart pub get
dart run bin/dev_relay.dart            # listens on 0.0.0.0:7777
```

The relay keeps alerts in memory, enforces the RoadTo write policy and logs
rejections. Default addresses in the app:

| Where the app runs | Relay address |
| --- | --- |
| Android emulator | `ws://10.0.2.2:7777` (default) |
| iOS simulator | `ws://127.0.0.1:7777` (default) |
| Real phone, same Wi-Fi | `ws://<computer IP>:7777`, set in Réglages |

## 2. The app

```bash
cd app
flutter pub get
flutter run
```

1. **Où allez-vous ?**: type an address ("Part-Dieu, Lyon"), or long-press
   the map and tap **Y aller**.
2. Simulated driving starts (50 km/h, adjustable). The top banner shows the
   next maneuver, the bottom bar the arrival time.
3. **Signaler** (big orange button): pick a type; it is sent after 5 s
   unless cancelled.

Without simulation (Réglages > Conduite simulée) the app follows the GPS:
only with a passenger.

## 3. Offline map and search

Builds from CI (the APK and simulator artifacts) **embed the Lyon region**:
on first launch the app installs it (a progress bar shows in Réglages >
Régions hors ligne), then the map and address search work in airplane mode.
Routing still needs the network until valhalla-mobile is integrated.

A local `flutter run` has no embedded region unless you run
`tool/embed_region.sh lyon` first (needs the `gh` CLI and access to the
repository). Otherwise import `lyon.roadto`, downloaded from the
`region-lyon` release: Réglages > Régions hors ligne > **Importer un fichier
.roadto**. Either way the app checks the signature and every file hash
before installing.

## 4. Two phones, one alert

Exit criterion of milestone J3, by hand:

1. Start the relay on the computer and two app instances (two emulators, or
   an emulator and a simulator) pointing at it.
2. On A, start a trip and report **Route fermée**.
3. On B, start a trip through the same place: the alert appears on the map,
   then "Route fermée dans …". B reroutes around it.
4. When B passes within 150 m of an alert, **toujours là ?** shows up. Two
   "Non" make it disappear.

The same scenario runs automatically in `relay/dev_relay/test/`.

## POC limitations

| Topic | POC | Target |
| --- | --- | --- |
| Map | offline PMTiles for Lyon, online OpenFreeMap tiles elsewhere | one package per region (J2), France-wide (V1) |
| Routing | public FOSSGIS Valhalla server | valhalla-mobile on the phone (J2); the graph is already in the package |
| Search | offline SQLite FTS5 index, Photon online as fallback | offline only, plus categories (J5) |
| Guidance | in-house Dart engine | in-house or Ferrostar (spike C) |
| Relay | in-memory dev relay | strfry + plugin, two synchronized relays (J3) |
| Identity | key in Keystore / Keychain | + BIP-39 recovery phrase (J3) |
| Android location | geolocator, LocationManager forced | plugin without Google services (J2) |
| Car | — | Android Auto (J4), CarPlay (after Apple's approval) |
| Police alerts | disabled | after the L130-11 channel (J6) |

The public servers (OpenFreeMap, FOSSGIS, Komoot) are free services:
reasonable test use only.
