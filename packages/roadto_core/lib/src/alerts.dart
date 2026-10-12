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

  RoadAlert({
    required this.id,
    required this.author,
    required this.type,
    required this.geohash,
    required this.createdAt,
    required this.expiresAt,
    this.bearing,
  });

  /// Centre de la maille 7 : la position exacte n'est jamais publiée.
  LatLon get position => geohashDecode(geohash).center;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  static RoadAlert? fromEvent(NostrEvent e) {
    if (e.kind != RoadToKinds.alert) return null;
    final type = AlertType.fromCode(e.tag('t'));
    final exp = e.expiration;
    final hashes = e.tagValues('g');
    if (type == null || exp == null || hashes.isEmpty) return null;
    final finest = hashes.reduce((a, b) => a.length >= b.length ? a : b);
    return RoadAlert(
      id: e.id,
      author: e.pubkey,
      type: type,
      geohash: finest,
      createdAt: DateTime.fromMillisecondsSinceEpoch(e.createdAt * 1000, isUtc: true),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      bearing: int.tryParse(e.tag('bearing') ?? ''),
    );
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
}) {
  if (type == AlertType.police && !FeatureFlags.policeAlerts) {
    throw StateError('Les alertes police sont désactivées');
  }
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
      ['expiration', '${_unix(t.add(type.ttl))}'],
      if (bearing != null) ['bearing', '${((bearing / 10).round() * 10) % 360}'],
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

  AlertStore({this.visibilityThreshold = 0.35});

  /// Intègre un événement reçu. Renvoie true s'il a changé l'état.
  bool ingest(NostrEvent e, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (e.isExpired(t) || e.powBits < PowPolicy.forKind(e.kind)) return false;
    switch (e.kind) {
      case RoadToKinds.alert:
        final alert = RoadAlert.fromEvent(e);
        if (alert == null || _alerts.containsKey(alert.id)) return false;
        if (alert.type == AlertType.police && !FeatureFlags.policeAlerts) return false;
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
  }
}
