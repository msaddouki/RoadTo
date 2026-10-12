import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

/// Annonces vocales par la synthèse du système, hors ligne quand la voix
/// française est installée.
class Voice {
  final _tts = FlutterTts();
  bool enabled = true;
  bool _ready = false;

  Future<void> init() async {
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(Platform.isIOS ? 0.5 : 0.9);
      if (Platform.isIOS) {
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers,
        ]);
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> say(String text) async {
    if (!enabled || !_ready || text.isEmpty) return;
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
