import 'dart:io' show Platform;

import 'package:roadto_core/roadto_core.dart';

/// Réglages par défaut du POC. Les services publics ci-dessous servent au POC
/// seulement : la carte, le routage et la recherche passeront hors ligne au
/// jalon J2 (PMTiles, valhalla-mobile, index SQLite).
abstract final class Defaults {
  /// Styles OpenFreeMap : tuiles OSM gratuites, sans clé ni traceur.
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
