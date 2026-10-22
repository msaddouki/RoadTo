import 'dart:math' as math;

import 'geo.dart';
import 'geohash.dart';
import 'nostr/event.dart';
import 'nostr/filter.dart';
import 'nostr/keys.dart';

/// Kinds Nostr de RoadTo (plage « regular » 1000–9999). Provisoires : à
/// figer dans l'ADR 0005 avant la bêta.
abstract final class RoadToKinds {
  static const alert = 4550;
  static const confirmation = 4551;
  static const all = [alert, confirmation];
}

/// Interrupteurs fonctionnels. Les alertes police restent coupées tant que le
/// canal L130-11 (jalon J6) n'est pas en place et validé.
abstract final class FeatureFlags {
  static const policeAlerts = false;
}

/// Preuve de travail minimale exigée (NIP-13), en bits.
abstract final class PowPolicy {
  static const alert = 12;
  static const confirmation = 8;

  static int forKind(int kind) => kind == RoadToKinds.alert ? alert : confirmation;
}

/// Précisions des tags géohash publiés : de la région (4, ~20 km) au point
/// (7, ~150 m). On ne publie jamais une position plus fine que la maille 7.
const alertGeohashPrecisions = [4, 5, 6, 7];

/// Précision des mailles auxquelles l'app s'abonne.
const subscriptionGeohashPrecision = 5;

enum AlertType {
  accident('accident', 'Accident', Duration(minutes: 60), blocksRoad: true),
  traffic('traffic', 'Bouchon', Duration(minutes: 30)),
  hazard('hazard', 'Danger', Duration(minutes: 45)),
  closure('closure', 'Route fermée', Duration(hours: 6), blocksRoad: true),
  roadworks('roadworks', 'Travaux', Duration(hours: 12)),
  police('police', 'Police', Duration(minutes: 60));

  final String code;
  final String label;
  final Duration ttl;
  final bool blocksRoad;

  const AlertType(this.code, this.label, this.ttl, {this.blocksRoad = false});

  /// Types proposés à l'utilisateur, selon les interrupteurs.
  static List<AlertType> get reportable => [
    for (final t in values)
      if (t != police || FeatureFlags.policeAlerts) t,
  ];

  static AlertType? fromCode(String? code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// How bad a jam is, when the report says (tag `level`): the speed it is
/// crawled at counts in the time to arrival.
enum JamLevel {
  slow('slow', 'Ralenti', 25, '#FF9F1C'),
  jam('jam', 'Bouchon', 10, '#E53935'),
  stopped('stopped', 'À l’arrêt', 5, '#8E1B1B');

  final String code;
  final String label;
  final double kph;

  /// Colour of the jammed stretch on the map: orange, red, dark red.
  final String color;

  const JamLevel(this.code, this.label, this.kph, this.color);

  static JamLevel? fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// Traffic information published from open data by RoadTo's own robot
/// (relay/traffic_bot): its alerts carry their source (tag `src`, "source/site"),
/// shown with them, and each site's newest alert replaces the previous one.
/// Only the keys below are believed: anyone else's `src` tag is ignored.
abstract final class TrafficSources {
  /// Public keys of the robot (relay/traffic_bot, ROADTO_TRAFFIC_KEY).
  static const keys = {'72207f9f4206976cdbbfe80fddb9fae6cd852459c1f8f1154a4e05d5ff6c235e'};

  static const labels = {'bison-fute': 'Bison Futé', 'grandlyon': 'Métropole de Lyon'};

  /// Longest jam a report may describe, in metres.
  static const maxLengthM = 20000;

  /// The jammed stretch's geometry (tag `shape`, polyline precision 6), at
  /// most this long and this many points; believed from the robot only.
  static const maxShapeChars = 4000;
  static const maxShapePoints = 400;
}

/// Alerte routière décodée d'un événement Nostr.
class RoadAlert {
  final String id;
  final String author;
  final AlertType type;
  final String geohash;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// Cap du signaleur au moment du signalement, arrondi à 10°.
  final int? bearing;

  /// For a jam: how bad, and how long (metres), when the report says.
  final JamLevel? level;
  final int? lengthM;

  /// "bison-fute/MQA01.E1": open data published by RoadTo's robot
  /// ([TrafficSources]); null for drivers' reports.
  final String? source;

  /// The jammed stretch along the road, in the direction of traffic, from
  /// the robot ([TrafficSources]); drawn in the [level]'s colour.
  final List<LatLon>? shape;

  RoadAlert({
    required this.id,
    required this.author,
    required this.type,
    required this.geohash,
    required this.createdAt,
    required this.expiresAt,
    this.bearing,
    this.level,
    this.lengthM,
    this.source,
    this.shape,
  });

  /// "Bouchon", "À l’arrêt": the level when the report gives it.
  String get headline => level?.label ?? type.label;

  /// "Bison Futé", for alerts from open data.
  String? get sourceLabel {
    final s = source;
    if (s == null) return null;
    return TrafficSources.labels[s.split('/').first] ?? s.split('/').first;
  }

  /// Centre de la maille 7 : la position exacte n'est jamais publiée.
  LatLon get position => geohashDecode(geohash).center;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  static RoadAlert? fromEvent(NostrEvent e, {Set<String> trustedSources = TrafficSources.keys}) {
    if (e.kind != RoadToKinds.alert) return null;
    final type = AlertType.fromCode(e.tag('t'));
    final exp = e.expiration;
    final hashes = e.tagValues('g');
    if (type == null || exp == null || hashes.isEmpty) return null;
    final finest = hashes.reduce((a, b) => a.length >= b.length ? a : b);
    final length = int.tryParse(e.tag('length') ?? '');
    return RoadAlert(
      id: e.id,
      author: e.pubkey,
      type: type,
      geohash: finest,
      createdAt: DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000, isUtc: true),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      bearing: int.tryParse(e.tag('bearing') ?? ''),
      level: type == AlertType.traffic ? JamLevel.fromCode(e.tag('level')) : null,
      lengthM: type == AlertType.traffic && length != null && length > 0 && length <= TrafficSources.maxLengthM
          ? length
          : null,
      source: trustedSources.contains(e.pubkey) ? e.tag('src') : null,
      shape: type == AlertType.traffic && trustedSources.contains(e.pubkey) ? _shape(e.tag('shape')) : null,
    );
  }

  static List<LatLon>? _shape(String? encoded) {
    if (encoded == null || encoded.isEmpty || encoded.length > TrafficSources.maxShapeChars) return null;
    try {
      final points = decodePolyline(encoded);
      return points.length >= 2 && points.length <= TrafficSources.maxShapePoints ? points : null;
    } catch (_) {
      return null;
    }
  }
}

int _unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// Construit l'événement d'un signalement.
NostrEvent buildAlertEvent({
  required KeyPair keys,
  required AlertType type,
  required LatLon position,
  double? bearing,
  DateTime? now,
  JamLevel? level,
  int? lengthM,
  String? source,
  List<LatLon>? shape,
  Duration? lasting,
}) {
  if (type == AlertType.police && !FeatureFlags.policeAlerts) {
    throw StateError('Les alertes police sont désactivées');
  }
  final ttl = lasting == null || lasting > type.ttl ? type.ttl : lasting;
  final t = now ?? DateTime.now();
  final hash = geohashEncode(position, precision: alertGeohashPrecisions.last);
  return NostrEvent.create(
    keys: keys,
    kind: RoadToKinds.alert,
    createdAt: t,
    powDifficulty: PowPolicy.alert,
    tags: [
      ['t', type.code],
      for (final p in alertGeohashPrecisions) ['g', hash.substring(0, p)],
      ['expiration', '${_unix(t.add(ttl))}'],
      if (bearing != null) ['bearing', '${((bearing / 10).round() * 10) % 360}'],
      if (level != null) ['level', level.code],
      if (lengthM != null) ['length', '$lengthM'],
      if (source != null) ['src', source],
      if (shape != null && shape.length >= 2) ['shape', encodePolyline(shape)],
    ],
  );
}

/// Construit la réponse à « toujours là ? ».
NostrEvent buildConfirmationEvent({
  required KeyPair keys,
  required RoadAlert alert,
  required bool stillThere,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  return NostrEvent.create(
    keys: keys,
    kind: RoadToKinds.confirmation,
    createdAt: t,
    powDifficulty: PowPolicy.confirmation,
    tags: [
      ['e', alert.id],
      for (final p in alertGeohashPrecisions) ['g', alert.geohash.substring(0, p)],
      ['still', stillThere ? 'yes' : 'no'],
      ['expiration', '${_unix(alert.expiresAt)}'],
    ],
  );
}

/// Filtre d'abonnement aux alertes et confirmations de mailles géohash.
NostrFilter alertFilter(Iterable<String> geohashes, {DateTime? now}) {
  final t = now ?? DateTime.now();
  final maxTtl = AlertType.values.map((a) => a.ttl).reduce((a, b) => a > b ? a : b);
  return NostrFilter(kinds: RoadToKinds.all, tags: {'g': geohashes.toList()..sort()}, since: _unix(t.subtract(maxTtl)));
}

class _Confirmation {
  final bool stillThere;
  final DateTime at;

  _Confirmation(this.stillThere, this.at);
}

/// Alertes connues et leurs confirmations, avec un score de fiabilité calculé
/// localement.
class AlertStore {
  final _alerts = <String, RoadAlert>{};

  /// alerte -> auteur de la confirmation -> dernière réponse.
  final _confirmations = <String, Map<String, _Confirmation>>{};

  /// Seuil de score sous lequel une alerte n'est plus affichée.
  final double visibilityThreshold;

  /// Keys whose `src` tag is believed ([TrafficSources]).
  final Set<String> trustedSources;

  /// source ("bison-fute/MQA01.E1") -> its newest alert.
  final _bySource = <String, String>{};

  AlertStore({this.visibilityThreshold = 0.35, this.trustedSources = TrafficSources.keys});

  /// Intègre un événement reçu. Renvoie true s'il a changé l'état.
  bool ingest(NostrEvent e, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (e.isExpired(t) || e.powBits < PowPolicy.forKind(e.kind)) return false;
    switch (e.kind) {
      case RoadToKinds.alert:
        final alert = RoadAlert.fromEvent(e, trustedSources: trustedSources);
        if (alert == null || _alerts.containsKey(alert.id)) return false;
        if (alert.type == AlertType.police && !FeatureFlags.policeAlerts) return false;
        // A site's newest alert replaces the previous one; an older one is late.
        if (alert.source case final source?) {
          final previous = _alerts[_bySource[source]];
          if (previous != null) {
            if (!previous.createdAt.isBefore(alert.createdAt)) return false;
            _alerts.remove(previous.id);
            _confirmations.remove(previous.id);
          }
          _bySource[source] = alert.id;
        }
        _alerts[alert.id] = alert;
        return true;
      case RoadToKinds.confirmation:
        final alertId = e.tag('e');
        final still = e.tag('still');
        if (alertId == null || (still != 'yes' && still != 'no')) return false;
        if (_alerts[alertId]?.author == e.pubkey) return false;
        final byAuthor = _confirmations.putIfAbsent(alertId, () => {});
        final at = DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000, isUtc: true);
        final previous = byAuthor[e.pubkey];
        if (previous != null && !previous.at.isBefore(at)) return false;
        byAuthor[e.pubkey] = _Confirmation(still == 'yes', at);
        return true;
    }
    return false;
  }

  RoadAlert? operator [](String id) => _alerts[id];

  Iterable<RoadAlert> get all => _alerts.values;

  /// Score de 0 à 1. Une alerte neuve vaut 1 et perd du crédit en vieillissant
  /// (0,7 à mi-vie) ; chaque « oui » la rafraîchit, chaque « non » pèse plus
  /// lourd qu'un « oui ». Les réponses récentes comptent davantage : deux
  /// « non » récents suffisent à masquer une alerte non confirmée.
  double reliability(String alertId, {DateTime? now}) {
    final alert = _alerts[alertId];
    if (alert == null) return 0;
    final t = now ?? DateTime.now();
    final halfLife = alert.type.ttl.inSeconds / 2;
    double weight(DateTime at) => math.pow(0.5, t.difference(at).inSeconds / halfLife).toDouble();

    var yes = 0.0, no = 0.0;
    var lastYes = alert.createdAt;
    for (final c in (_confirmations[alertId] ?? const {}).values) {
      if (c.stillThere) {
        yes += weight(c.at);
        if (c.at.isAfter(lastYes)) lastYes = c.at;
      } else {
        no += weight(c.at);
      }
    }
    final freshness = 0.4 + 0.6 * weight(lastYes);
    final support = (1.5 + yes) / (1.5 + yes + 2 * no);
    return freshness * support;
  }

  /// Drivers whose latest answer is "still there", and when the most recent
  /// of them said so: "Confirmé par 3 conducteurs · il y a 4 min".
  ({int count, DateTime? latest}) stillThere(String alertId) {
    var count = 0;
    DateTime? latest;
    for (final c in (_confirmations[alertId] ?? const {}).values) {
      if (!c.stillThere) continue;
      count++;
      if (latest == null || c.at.isAfter(latest)) latest = c.at;
    }
    return (count: count, latest: latest);
  }

  /// Alertes à afficher : non expirées et jugées fiables.
  List<RoadAlert> visible({DateTime? now}) {
    final t = now ?? DateTime.now();
    return [
      for (final a in _alerts.values)
        if (!a.isExpired(t) && reliability(a.id, now: t) >= visibilityThreshold) a,
    ];
  }

  /// Oublie les alertes expirées et leurs confirmations.
  void purge({DateTime? now}) {
    final t = now ?? DateTime.now();
    final expired = [
      for (final a in _alerts.values)
        if (a.isExpired(t)) a.id,
    ];
    for (final id in expired) {
      _alerts.remove(id);
      _confirmations.remove(id);
    }
    _bySource.removeWhere((_, id) => !_alerts.containsKey(id));
  }
}
