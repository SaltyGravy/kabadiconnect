import 'package:flutter_tts/flutter_tts.dart';

import '../constants.dart';

/// Wraps flutter_tts for the brief's "spoken price information" and
/// "audio-based safety guidance" requirements. Uses on-device platform TTS
/// engines, so it works offline once the language voice pack is installed
/// (standard on modern Android with Hindi/Marathi support).
class TtsService {
  final FlutterTts _tts = FlutterTts();

  static const Map<AppLocale, String> _ttsLocale = {
    AppLocale.en: 'en-IN',
    AppLocale.hi: 'hi-IN',
    AppLocale.mr: 'mr-IN',
  };

  /// Deliberately slow default (~half normal pace): this narrates safety
  /// warnings and prices to a low-literacy audience who may be hearing the
  /// term for the first time, not reading along a transcript at speed.
  Future<void> speak(String text, AppLocale locale, {double rate = 0.4}) async {
    try {
      await _tts.stop();
      await _tts.setLanguage(_ttsLocale[locale] ?? 'en-IN');
      await _tts.setSpeechRate(rate);
      await _tts.speak(text);
    } catch (_) {
      // TTS voice pack missing / unsupported platform -- fail silently,
      // the UI text itself remains the primary channel.
    }
  }

  Future<void> stop() => _tts.stop();
}
