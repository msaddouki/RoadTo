import 'alerts.dart';
import 'geohash.dart';
import 'nostr/event.dart';

/// Politique d'écriture des relais RoadTo. Le relais de dev l'applique telle
/// quelle ; le plugin strfry de production devra donner les mêmes verdicts
/// (vecteurs de test partagés).
///
/// Renvoie null si l'événement est accepté, sinon la raison du refus, préfixée
/// comme le veut NIP-01 (« invalid: », « pow: », « blocked: »).
String? checkWritePolicy(NostrEvent e, {DateTime? now, bool policeAllowed = FeatureFlags.policeAlerts}) {
  final t = now ?? DateTime.now();
  final nowS = t.millisecondsSinceEpoch ~/ 1000;

  if (!RoadToKinds.all.contains(e.kind)) return 'blocked: kind ${e.kind} non accepté';
  if (!e.verify()) return 'invalid: identifiant ou signature';
  if (e.createdAt > nowS + 300) return 'invalid: date dans le futur';
  if (e.powBits < PowPolicy.forKind(e.kind)) {
    return 'pow: ${PowPolicy.forKind(e.kind)} bits requis';
  }

  final exp = e.expiration;
  if (exp == null) return 'invalid: expiration manquante';
  if (exp <= nowS) return 'invalid: déjà expiré';

  final hashes = e.tagValues('g');
  if (hashes.isEmpty || !hashes.every(isValidGeohash)) return 'invalid: géohash';
  final finest = hashes.reduce((a, b) => a.length >= b.length ? a : b);
  if (finest.length > alertGeohashPrecisions.last) return 'invalid: géohash trop précis';
  if (!hashes.every(finest.startsWith)) return 'invalid: géohash incohérent';

  if (e.kind == RoadToKinds.alert) {
    final type = AlertType.fromCode(e.tag('t'));
    if (type == null) return 'invalid: type inconnu';
    if (type == AlertType.police && !policeAllowed) return 'blocked: alertes police désactivées';
    if (e.content.isNotEmpty) return 'invalid: texte libre interdit';
    if (exp > e.createdAt + type.ttl.inSeconds + 60) return 'invalid: expiration trop lointaine';
  } else {
    if (e.tag('e') == null) return 'invalid: alerte visée manquante';
    final still = e.tag('still');
    if (still != 'yes' && still != 'no') return 'invalid: réponse attendue yes ou no';
    final maxTtl = AlertType.values.map((a) => a.ttl.inSeconds).reduce((a, b) => a > b ? a : b);
    if (exp > e.createdAt + maxTtl) return 'invalid: expiration trop lointaine';
  }
  return null;
}
