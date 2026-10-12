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
  /// Regions shipped inside the app, installed on first launch. CI copies the
  /// signed packages into `assets/regions/<id>/` before building; a local build
  /// without them simply has no embedded region.
  static const embeddedRegions = ['lyon'];

  /// Regions offered for download from a server. Empty until a package host
  /// (MinIO, see docs/adr/0009) is set up; regions come embedded or from a
  /// `.roadto` file meanwhile.
  static const regions = <RegionSource>[];

  /// Ed25519 public keys (base64) allowed to sign region manifests; the
  /// matching private key is the REGION_SIGNING_KEY secret of the repository.
  /// To rotate: `python -m roadto_pipeline keygen`, replace the secret, add
  /// the new key here and drop the old one after one release.
  static const trustedRegionKeys = <String>[
    '7hKf0Z8kswZm/IeEVc7gHvx7IrW0cMEGYBA704fp8Kc=', // 2026-10-12, POC key
  ];

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
