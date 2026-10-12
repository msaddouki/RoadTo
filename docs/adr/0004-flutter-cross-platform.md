# ADR 0004 — One Flutter app for Android and iOS, Dart core

- Status: accepted (POC), to be confirmed at the end of J1
- Date: 2026-10-12
- Replaces: "0004 Rust core + native UIs" from the development plan

## Context

The plan called for a Rust core exposed through UniFFI, a native Android app
(Kotlin, Compose) and then, after the Android beta, a native iOS app (Swift,
SwiftUI): about 40 more days for iOS and CarPlay, and two mobile languages to
learn for a single developer new to mobile.

New requirement: target Android and iOS from the start.

## Decision

- **One Flutter app** (`app/`) for both phones: one language (Dart), one UI
  codebase.
- **A pure Dart core** (`packages/roadto_core/`), with no Flutter dependency:
  geohash, Nostr events (BIP-340 signatures, NIP-13 proof of work, NIP-40
  expiry), alerts and reliability, relay write policy, guidance, simulation,
  offline regions and search. Tested in CI without an emulator.
- **Car screens stay native**, in the app's `android/` and `ios/` folders:
  Android Auto (Car App Library, Kotlin) and CarPlay (templates, Swift) cannot
  host a Flutter view. They will talk to the Dart core over MethodChannels.
  These are the only native parts planned.

## Consequences

- iOS moves forward together with Android: milestone J8 shrinks to CarPlay,
  App Store publishing and iOS-specific settings.
- Ferrostar has no Flutter binding: the POC uses an in-house guidance engine
  (`GuidanceEngine`). Spike C will tell whether it is enough or whether
  Ferrostar must be plugged in through native plugins.
- valhalla-mobile (offline routing) has to be exposed to Dart through a
  plugin (FFI or MethodChannel): to be measured in spike B.
- Rust remains possible later for a specific piece (crypto, Valhalla) through
  `flutter_rust_bridge`, if a measurement justifies it.
- Known debt: `geolocator` ships `play-services-location` on Android. The app
  forces the platform LocationManager (no call to Google services at run
  time), but CI flags it. To be replaced in J2 by a small LocationManager /
  CoreLocation plugin.

## Alternatives considered

- **Kotlin Multiplatform + Compose Multiplatform**: good for Android Auto,
  but the KMP Gradle setup and the iOS toolchain are heavy for a beginner.
- **React Native**: decent mapping ecosystem, but one more JS layer between
  the map and the guidance.
- **Native ×2** (initial plan): best integration, twice the work.
