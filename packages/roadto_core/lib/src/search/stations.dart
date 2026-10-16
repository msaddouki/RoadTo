import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../geo.dart';
import '../regions/manifest.dart';
import 'categories.dart';
import 'geocoder.dart';

/// Fuels of the official price feed, in the order shown to the user.
const fuelLabels = {'gazole': 'Gazole', 'e10': 'SP95-E10', 'sp95': 'SP95', 'sp98': 'SP98', 'e85': 'E85', 'gplc': 'GPL'};

class FuelPrice {
  /// Euros per litre.
  final double price;
  final DateTime updated;

  const FuelPrice(this.price, this.updated);
}

/// A station of the official fuel price feed (prix-carburants.gouv.fr).
class FuelStation {
  final String id;
  final LatLon position;
  final String address;
  final String city;
  final bool motorway;
  final bool card24h;
  final Map<String, FuelPrice> prices;
  final List<String> outOfStock;

  const FuelStation({
    required this.id,
    required this.position,
    this.address = '',
    this.city = '',
    this.motorway = false,
    this.card24h = false,
    this.prices = const {},
    this.outOfStock = const [],
  });
}

/// A station of the national charging point base (IRVE), its charge points
/// grouped.
class ChargingStation {
  final String id;
  final LatLon position;
  final String name;
  final String operator;
  final String address;
  final int points;
  final double maxKw;

  /// `type2`, `ccs`, `chademo`, `ef` (household socket), `other`.
  final List<String> connectors;
  final bool free;
  final bool card;
  final bool openToAll;
  final bool alwaysOpen;

  const ChargingStation({
    required this.id,
    required this.position,
    this.name = '',
    this.operator = '',
    this.address = '',
    this.points = 1,
    this.maxKw = 0,
    this.connectors = const [],
    this.free = false,
    this.card = false,
    this.openToAll = true,
    this.alwaysOpen = false,
  });
}

/// The stations file of a region (pipeline/roadto_pipeline/stations.py):
/// fuel prices and charging points from official open data, refreshed every
/// few hours, separate from the region package.
class Stations {
  static const formatVersion = 1;

  final String regionId;
  final DateTime generated;
  final List<FuelStation> fuel;
  final List<ChargingStation> charging;

  const Stations({required this.regionId, required this.generated, this.fuel = const [], this.charging = const []});

  /// Reads the gzipped JSON file. Throws [FormatException] if it is not one.
  factory Stations.decode(List<int> gzipped) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(gzip.decode(gzipped)));
    } on Exception catch (e) {
      throw FormatException('Fichier des stations illisible : $e');
    }
    if (json is! Map<String, dynamic> || json['format'] != formatVersion) {
      throw const FormatException('Format du fichier des stations inconnu');
    }
    LatLon pos(Map<String, dynamic> s) => LatLon((s['lat'] as num).toDouble(), (s['lon'] as num).toDouble());
    return Stations(
      regionId: json['region'] as String,
      generated: DateTime.parse(json['generated'] as String),
      fuel: [
        for (final s in (json['fuel'] as List).cast<Map<String, dynamic>>())
          FuelStation(
            id: s['id'] as String,
            position: pos(s),
            address: s['address'] as String? ?? '',
            city: s['city'] as String? ?? '',
            motorway: s['motorway'] as bool? ?? false,
            card24h: s['card_24_7'] as bool? ?? false,
            prices: {
              for (final MapEntry(:key, :value) in (s['prices'] as Map<String, dynamic>).entries)
                key: FuelPrice(
                  ((value as Map<String, dynamic>)['price'] as num).toDouble(),
                  DateTime.parse(value['updated'] as String),
                ),
            },
            outOfStock: [for (final f in s['out_of_stock'] as List? ?? const []) '$f'],
          ),
      ],
      charging: [
        for (final s in (json['charging'] as List).cast<Map<String, dynamic>>())
          ChargingStation(
            id: s['id'] as String,
            position: pos(s),
            name: s['name'] as String? ?? '',
            operator: s['operator'] as String? ?? '',
            address: s['address'] as String? ?? '',
            points: s['points'] as int? ?? 1,
            maxKw: (s['max_kw'] as num? ?? 0).toDouble(),
            connectors: [for (final c in s['connectors'] as List? ?? const []) '$c'],
            free: s['free'] as bool? ?? false,
            card: s['card'] as bool? ?? false,
            openToAll: s['open_to_all'] as bool? ?? true,
            alwaysOpen: s['always_open'] as bool? ?? false,
          ),
      ],
    );
  }

  /// Places of [category] from this file, inside the box: fuel stations for
  /// `fuel`, charging stations for `charging`, nothing otherwise.
  List<StationCandidate> inBox(PlaceCategory category, double minLat, double maxLat, double minLon, double maxLon) {
    bool inside(LatLon p) => p.lat >= minLat && p.lat <= maxLat && p.lon >= minLon && p.lon <= maxLon;
    return switch (category.id) {
      'fuel' => [
        for (final s in fuel)
          if (inside(s.position)) StationCandidate(_fuelPlace(s), s.position, fuel: s),
      ],
      'charging' => [
        for (final s in charging)
          if (inside(s.position)) StationCandidate(_chargingPlace(s), s.position, charging: s),
      ],
      _ => const [],
    };
  }

  static Place _fuelPlace(FuelStation s) => Place(
    name: s.motorway ? 'Station-service (autoroute)' : 'Station-service',
    detail: [s.address, _tidyCity(s.city)].where((p) => p.isNotEmpty).join(', '),
    position: s.position,
    category: 'amenity=fuel',
  );

  static Place _chargingPlace(ChargingStation s) => Place(
    name: s.operator.isNotEmpty ? s.operator : (s.name.isNotEmpty ? s.name : 'Borne de recharge'),
    detail: _tidyAddress(s.address.isNotEmpty ? s.address : s.name),
    position: s.position,
    category: 'amenity=charging_station',
  );

  /// "MONTLUEL" -> "Montluel"; mixed case is kept.
  static String _tidyCity(String city) {
    if (city != city.toUpperCase()) return city;
    return city
        .toLowerCase()
        .split(RegExp(r'(?=[ -])|(?<=[ -])'))
        .map((w) => w.isEmpty || w == ' ' || w == '-' ? w : w[0].toUpperCase() + w.substring(1))
        .join();
  }

  /// Some operators write "[12 Rue X][69003][Lyon]".
  static String _tidyAddress(String a) =>
      a.replaceAll('][', ', ').replaceAll(RegExp(r'[\[\]]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// A place a category search may return, with the official station data
/// attached when there is one.
class StationCandidate {
  final Place place;
  final LatLon position;
  final FuelStation? fuel;
  final ChargingStation? charging;

  const StationCandidate(this.place, this.position, {this.fuel, this.charging});
}

/// How far an official station can be from the OSM place it stands for: the
/// fuel feed's positions are often 50 to 150 m off; charging points are
/// positioned closely and stand near each other.
const _matchM = {'fuel': 150.0, 'charging': 60.0};

/// OSM places and official stations of [category] as one list. An official
/// station close to an OSM place is attached to it (OSM keeps the name, often
/// the brand); the others become places of their own. Each station and each
/// place is used once, closest pairs first.
List<StationCandidate> mergeStations(
  PlaceCategory category,
  List<(Place, LatLon)> osm,
  List<StationCandidate> official,
) {
  final maxM = _matchM[category.id];
  if (maxM == null || official.isEmpty) return [for (final (place, p) in osm) StationCandidate(place, p)];
  final pairs = <(double, int, int)>[];
  for (var i = 0; i < osm.length; i++) {
    for (var j = 0; j < official.length; j++) {
      final d = distanceM(osm[i].$2, official[j].position);
      if (d <= maxM) pairs.add((d, i, j));
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  final osmTaken = <int, int>{}, officialTaken = <int>{};
  for (final (_, i, j) in pairs) {
    if (osmTaken.containsKey(i) || officialTaken.contains(j)) continue;
    osmTaken[i] = j;
    officialTaken.add(j);
  }
  return [
    for (var i = 0; i < osm.length; i++)
      if (osmTaken[i] case final j?)
        StationCandidate(osm[i].$1, osm[i].$2, fuel: official[j].fuel, charging: official[j].charging)
      else
        StationCandidate(osm[i].$1, osm[i].$2),
    for (var j = 0; j < official.length; j++)
      if (!officialTaken.contains(j)) official[j],
  ];
}

/// Keeps the stations file of each region on the device and refreshes it
/// from its publication URL. The whole file of the region is downloaded,
/// never stations "around me", and it is only kept if signed by a trusted
/// key.
class StationsStore {
  final Directory dir;
  final List<String> trustedKeys;
  final http.Client _client;

  StationsStore(this.dir, {required this.trustedKeys, http.Client? client}) : _client = client ?? http.Client();

  File _file(String regionId) => File('${dir.path}/$regionId.json.gz');

  /// The stored file of [regionId], or null if none or unreadable.
  Future<Stations?> load(String regionId) async {
    final f = _file(regionId);
    if (!await f.exists()) return null;
    try {
      final s = Stations.decode(await f.readAsBytes());
      return s.regionId == regionId ? s : null;
    } on FormatException {
      return null;
    }
  }

  /// Downloads the file of [regionId] from [url] (its signature at
  /// `<url>.sig`), checks it and stores it unless the stored one is newer.
  /// Returns the stations now stored. Throws on network or check failure.
  Future<Stations> refresh(String regionId, Uri url) async {
    if (trustedKeys.isEmpty) throw StateError('Aucune clé de confiance configurée dans l’app');
    final responses = await Future.wait([_client.get(url), _client.get(Uri.parse('$url.sig'))]);
    for (final r in responses) {
      if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}', uri: r.request?.url);
    }
    final bytes = responses[0].bodyBytes;
    if (!await verifyManifestSignature(bytes, responses[1].body, trustedKeys)) {
      throw const FormatException('Signature du fichier des stations invalide');
    }
    final fresh = Stations.decode(bytes);
    if (fresh.regionId != regionId) throw FormatException('Fichier d’une autre région : ${fresh.regionId}');
    final current = await load(regionId);
    if (current != null && !fresh.generated.isAfter(current.generated)) return current;
    await dir.create(recursive: true);
    final tmp = File('${_file(regionId).path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file(regionId).path);
    return fresh;
  }
}
