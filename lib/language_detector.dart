import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class LanguageDetector {
  List<String>? _supportedLanguages;

  Future<void> loadSupportedLanguages(FlutterTts flutterTts) async {
    List<dynamic> languages = await flutterTts.getLanguages;
    _supportedLanguages = languages.map((lang) => lang.toString()).toList();
  }

  String? detectLanguage(String text, BuildContext context) {
    if (_supportedLanguages == null) {
      print("Supported languages not loaded.");
      return null;
    }

    String? codePrefix = _detectLanguageCode(text);

    if (codePrefix == null) {
      return null;
    }

    String? match = _supportedLanguages!.firstWhere(
          (lang) => lang.toLowerCase().startsWith(codePrefix),
      orElse: () => '',
    );

    if (match.isEmpty) {
      _showLanguageNotSupportedDialog(context, codePrefix);
      return null;
    }

    return match;
  }

  String? _detectLanguageCode(String text) {
    if (RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(text)) {
      return 'ja';
    } else if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(text)) {
      return 'zh';
    } else if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(text)) {
      return 'ko';
    } else if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) {
      return 'ar';
    } else if (RegExp(r'[\u0400-\u04FF]').hasMatch(text)) {
      return 'ru';
    } else if (RegExp(r'[\u0590-\u05FF]').hasMatch(text)) {
      return 'he';
    } else if (RegExp(r'[\u0370-\u03FF]').hasMatch(text)) {
      return 'el';
    } else if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) {
      return 'hi';
    } else if (RegExp(r'[\u0E00-\u0E7F]').hasMatch(text)) {
      return 'th';
    } else if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) {
      return 'ta';
    }
    return null;
  }

  void _showLanguageNotSupportedDialog(BuildContext context, String codePrefix) {
    Future.microtask(() {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Language not supported"),
            content: Text(
                "Language '$codePrefix' not supported on this device. "
                    "Install extra languages from the device settings."
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("OK"),
              ),
            ],
          );
        },
      );
    });
  }
}