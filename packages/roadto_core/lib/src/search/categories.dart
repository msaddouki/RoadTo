import 'geocoder.dart';
import 'stations.dart';

/// A kind of place drivers look for ("nearest fuel"), mapped to the `kind`
/// values of the offline index (pipeline/roadto_pipeline/places.py).
class PlaceCategory {
  final String id;

  /// Shown to the user, in French.
  final String label;
  final Set<String> kinds;

  const PlaceCategory(this.id, this.label, this.kinds);
}

const driverCategories = [
  PlaceCategory('fuel', 'Carburant', {'amenity=fuel'}),
  PlaceCategory('charging', 'Recharge', {'amenity=charging_station'}),
  PlaceCategory('parking', 'Parking', {'amenity=parking'}),
  PlaceCategory('rest', 'Aire de repos', {'highway=rest_area', 'highway=services'}),
  PlaceCategory('toilets', 'Toilettes', {'amenity=toilets'}),
  PlaceCategory('food', 'Restauration', {'amenity=restaurant', 'amenity=fast_food', 'amenity=cafe'}),
];

/// A place found by category, with how far it is.
class NearbyPlace {
  final Place place;

  /// Straight-line distance from the search position.
  final double distanceM;

  /// When searching along a route: distance along the route to the point
  /// closest to the place, and how far that point is from the place.
  final double? aheadM;
  final double? offRouteM;

  /// Official data of the place, when the stations file has it: fuel prices,
  /// or charge points.
  final FuelStation? fuel;
  final ChargingStation? charging;

  const NearbyPlace(this.place, this.distanceM, {this.aheadM, this.offRouteM, this.fuel, this.charging});
}
