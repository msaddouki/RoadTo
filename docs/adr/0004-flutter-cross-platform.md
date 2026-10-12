# ADR 0004 — Une seule app Flutter pour Android et iOS, cœur en Dart

- Statut : accepté (POC), à confirmer à la fin du J1
- Date : 2026-10-12
- Remplace : « 0004 cœur Rust + UI natives » du plan de développement

## Contexte

Le plan prévoyait un cœur Rust exposé par UniFFI, une app Android native
(Kotlin, Compose) puis, après la bêta Android, une app iOS native (Swift,
SwiftUI) : environ 40 jours de plus pour iOS et CarPlay, et deux langages
mobiles à apprendre pour une personne seule et débutante en mobile.

Nouvelle exigence : viser Android et iOS dès le départ.

## Décision

- **Une app Flutter** (`app/`) pour les deux téléphones : un seul langage
  (Dart), une seule base d'interface.
- **Un cœur en Dart pur** (`packages/roadto_core/`), sans dépendance à
  Flutter : géohash, événements Nostr (signature BIP-340, PoW NIP-13,
  expiration NIP-40), alertes et fiabilité, politique d'écriture des
  relais, guidage, simulation. Testé en CI sans émulateur.
- **Les écrans voiture restent natifs**, dans les dossiers `android/` et
  `ios/` de l'app : Android Auto (Car App Library, Kotlin) et CarPlay
  (templates, Swift) n'affichent pas de vue Flutter. Ils parleront au cœur
  Dart par MethodChannel. Ce sont les seules parties natives prévues.

## Conséquences

- iOS avance en même temps qu'Android : le jalon J8 se réduit à CarPlay,
  à la publication App Store et aux réglages propres à iOS.
- Ferrostar n'a pas de binding Flutter : le POC utilise un moteur de
  guidage maison (`GuidanceEngine`). Le spike C du J1 dira s'il suffit ou
  s'il faut brancher Ferrostar par des plugins natifs.
- valhalla-mobile (routage hors ligne) devra être exposé à Dart par un
  plugin (FFI ou MethodChannel) : à mesurer au spike B.
- Rust reste possible plus tard pour un morceau précis (crypto, Valhalla)
  via `flutter_rust_bridge`, si une mesure le justifie.
- Dette connue : `geolocator` embarque `play-services-location` sur
  Android. L'app force le LocationManager (pas d'appel aux services Google
  à l'exécution), mais la CI le signale. À remplacer au J2 par un petit
  plugin LocationManager / CoreLocation.

## Alternatives écartées

- **Kotlin Multiplatform + Compose Multiplatform** : bon pour Android Auto,
  mais Gradle KMP et la chaîne iOS sont lourds pour un débutant.
- **React Native** : écosystème carto correct, mais une couche JS de plus
  entre la carte et le guidage.
- **Natif ×2** (plan initial) : meilleure intégration, double travail.
