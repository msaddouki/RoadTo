import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/app_controller.dart';

enum FeedbackKind {
  bug('Un problème'),
  route('Un itinéraire ou une instruction faux'),
  alert('Une alerte'),
  idea('Une idée'),
  other('Autre chose');

  final String label;
  const FeedbackKind(this.label);
}

/// What a tester sends from Réglages > Envoyer un retour. Built on the phone
/// and shown in full before it goes, through the system's sharing (mail,
/// messaging): there is no RoadTo server to send it to.
@immutable
class FeedbackDetails {
  final String appVersion;
  final String platform;
  final bool simulate;
  final bool offlineMap;
  final bool routesOffline;
  final String? region;
  final int relays;

  const FeedbackDetails({
    required this.appVersion,
    required this.platform,
    required this.simulate,
    required this.offlineMap,
    required this.routesOffline,
    required this.region,
    required this.relays,
  });

  /// Nothing about where the tester is or goes: no position, no
  /// destination, no relay address.
  static Future<FeedbackDetails> of(AppController app) async {
    var version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    final region = app.activeRegion?.manifest;
    return FeedbackDetails(
      appVersion: version,
      platform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      simulate: app.settings.simulate,
      offlineMap: app.usingOfflineMap,
      routesOffline: app.routesOffline,
      region: region == null ? null : '${region.regionId} ${region.version}',
      relays: app.settings.relays.length,
    );
  }

  List<String> get lines => [
    'Version : $appVersion',
    'Système : $platform',
    'Conduite simulée : ${simulate ? 'oui' : 'non'}',
    'Carte hors ligne : ${offlineMap ? 'oui' : 'non'}',
    'Itinéraires sur le téléphone : ${routesOffline ? 'oui' : 'non'}',
    'Région : ${region ?? 'aucune'}',
    'Relais configurés : $relays',
  ];
}

/// The text shared, in the order a reader wants it.
String feedbackText({
  required FeedbackKind kind,
  required String message,
  FeedbackDetails? details,
  String? crashReport,
}) => [
  'Retour RoadTo : ${kind.label}',
  '',
  message.trim(),
  if (details != null) ...['', '-- Infos techniques --', ...details.lines],
  if (crashReport != null) ...['', '-- Dernier rapport d’erreur --', crashReport],
].join('\n');
