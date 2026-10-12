import 'dart:io' show Platform;

import 'package:roadto_core/roadto_core.dart';

/// A downloadable region package (built by pipeline/, see pipeline/README.md).
class RegionSource {
  final String id;
  final String name;
  final String manifestUrl;

  const RegionSource(this.id, this.name, this.manifestUrl);
}

/// POC defaults. The public online services below are for the POC only:
/// map and search already work offline once a region is installed; routing
/// moves offline with valhalla-mobile.
abstract final class Defaults {
  /// Regions offered for download. Packages are published to rolling GitHub
  /// Releases by .github/workflows/region.yml.
  static const regions = [
    RegionSource(
      'lyon',
      'Lyon et sa périphérie',
      'https://github.com/msaddouki/RoadTo/releases/download/region-lyon/manifest.json',
    ),
  ];

  /// Ed25519 public keys (base64) allowed to sign region manifests. Generate
  /// the pair with `python -m roadto_pipeline keygen`, store the private key
  /// as the REGION_SIGNING_KEY secret and add the public key here. Until then
  /// the app refuses every package.
  static const trustedRegionKeys = <String>[];

  /// OpenFreeMap styles: free OSM tiles, no key, no tracking.
  static const mapStyles = {
    'Liberty': 'https://tiles.openfreemap.org/styles/liberty',
    'Positron': 'https://tiles.openfreemap.org/styles/positron',
    'Bright': 'https://tiles.openfreemap.org/styles/bright',
  };
  static const mapStyle = 'https://tiles.openfreemap.org/styles/liberty';

  /// Valhalla public de la FOSSGIS : usage raisonnable, développement.
  static const routingUrl = 'https://valhalla1.openstreetmap.de/';

  /// Photon (Komoot) : géocodage OSM.
  static const geocoderUrl = 'https://photon.komoot.io/';

  /// Relais de dev lancé sur le poste (relay/dev_relay). L'émulateur Android
  /// voit le poste en 10.0.2.2, le simulateur iOS en 127.0.0.1. Sur un vrai
  /// téléphone, mettre l'adresse IP du poste dans les réglages.
  static List<String> get relays => [Platform.isAndroid ? 'ws://10.0.2.2:7777' : 'ws://127.0.0.1:7777'];

  /// Point de départ quand aucune position n'est connue (simulation) :
  /// place Bellecour, Lyon, région test du plan.
  static const fallbackPosition = LatLon(45.7578, 4.8320);

  static const simulationSpeedKmh = 50.0;
}
