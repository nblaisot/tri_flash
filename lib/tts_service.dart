import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service to manage Text-to-Speech (TTS) settings and playback
/// so that UI code doesn't deal directly with FlutterTts.
class TtsService {
  final FlutterTts _tts = FlutterTts();

  double _speechRate = 0.6;
  String _forcedLanguage = 'Auto';
  List<String> _supportedLanguages = const [];

  /// Initialize TTS and load available languages from the device.
  Future<void> initialize() async {
    await _tts.awaitSpeakCompletion(true);
    try {
      final langs = await _tts.getLanguages;
      _supportedLanguages = langs.cast<String>()..sort();
    } catch (e) {
      debugPrint('Error loading supported languages: $e');
      _supportedLanguages = [];
    }
  }

  /// Load persisted settings from SharedPreferences.
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _speechRate = prefs.getDouble('ttsSpeed') ?? 0.6;
    _forcedLanguage = prefs.getString('forcedLanguage') ?? 'Auto';
    await applySettings();
  }

  /// Save current settings to SharedPreferences.
  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ttsSpeed', _speechRate);
    await prefs.setString('forcedLanguage', _forcedLanguage);
  }

  /// Apply current settings to the TTS engine.
  Future<void> applySettings() async {
    await _tts.setSpeechRate(_speechRate);
    if (_forcedLanguage != 'Auto') {
      try {
        await _tts.setLanguage(_forcedLanguage);
      } catch (e) {
        debugPrint('Error setting language $_forcedLanguage: $e');
      }
    }
  }

  /// Getters for UI
  double get speechRate => _speechRate;
  String get forcedLanguage => _forcedLanguage;
  List<String> get supportedLanguages => _supportedLanguages;

  /// Update settings in memory and apply them to the TTS engine.
  Future<void> updateSettings({double? speed, String? forcedLang}) async {
    if (speed != null) {
      _speechRate = speed.clamp(0.1, 1.0);
    }
    if (forcedLang != null) {
      _forcedLanguage = forcedLang;
    }
    await applySettings();
  }

  /// Speak text, automatically setting the language if needed.
  Future<void> speak(String text, {BuildContext? context}) async {
    String? langToUse = _forcedLanguage;

    if (_forcedLanguage == 'Auto') {
      final prefix = _detectScriptPrefix(text);
      langToUse = prefix != null ? _resolveToSupportedVariant(prefix) : null;
      langToUse ??= 'en-US'; // final fallback
    }

    try {
      await _tts.setLanguage(langToUse);
    } catch (e) {
      // If device lacks that voice, fall back safely
      await _tts.setLanguage('en-US');
    }

    await _tts.setSpeechRate(_speechRate);
    await _tts.speak(text);
  }

  /// Stop speech.
  Future<void> stop() => _tts.stop();

  /// Pause speech (if supported on platform).
  Future<void> pause() => _tts.pause();

  /// Dispose resources (FlutterTts has no explicit dispose, so just stop).
  Future<void> dispose() async {
    await _tts.stop();
  }

  /// Helper: detect script → language prefix for TTS
  String? _detectScriptPrefix(String text) {
    // Cyrillic (Russian, etc.)
    if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) return 'ru';

    // CJK
    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) return 'zh'; // Chinese
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(text)) return 'ja'; // Japanese
    if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(text)) return 'ko'; // Korean

    // Arabic
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'ar';

    // Hebrew
    if (RegExp(r'[\u0590-\u05FF]').hasMatch(text)) return 'he';

    // Greek
    if (RegExp(r'[\u0370-\u03FF]').hasMatch(text)) return 'el';

    // Devanagari (Hindi, Marathi, Nepali, etc.)
    if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return 'hi';

    // Tamil
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'ta';

    // Thai
    if (RegExp(r'[\u0E00-\u0E7F]').hasMatch(text)) return 'th';

    return null; // unknown → fall back later
  }

  String? _resolveToSupportedVariant(String prefix) {
    // Find exact "ru" or any "ru-XX" in the device-supported list
    for (final lang in _supportedLanguages) {
      final lower = lang.toLowerCase();
      if (lower == prefix || lower.startsWith('$prefix-')) return lang;
    }
    return null;
  }
}