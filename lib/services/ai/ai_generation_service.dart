import 'dart:convert';
import 'dart:math';

import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';
import 'package:tri_flash/services/ai/vocabulary_matcher.dart';

class AiGenerationService {
  AiGenerationService({
    AiSettingsService? settings,
    AiProviderClientFactory? clientFactory,
  }) : settings = settings ?? AiSettingsService(),
       _clientFactory = clientFactory;

  final AiSettingsService settings;
  final AiProviderClientFactory? _clientFactory;

  Future<BilingualSentence> generateSentence(VocabularyEntry entry) async {
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();
    final data = await _generateJson('''
Create one natural example sentence and its faithful translation.

Requirements:
- The source sentence language is $sourceLanguage and must contain this exact vocabulary form: ${jsonEncode(entry.word)}.
- The translated sentence language is $translationLanguage and must contain this exact translated form: ${jsonEncode(entry.translation)}.
- Keep both sentences concise and semantically equivalent.
- Return exactly: {"source":"...","translation":"..."}
''');
    final source = data['source'] as String?;
    final translation = data['translation'] as String?;
    if (source == null ||
        translation == null ||
        source.isEmpty ||
        translation.isEmpty) {
      throw const FormatException('The sentence response is incomplete.');
    }
    return BilingualSentence(source: source, translation: translation);
  }

  Future<GeneratedText> generateText({
    required List<VocabularyEntry> availableVocabulary,
    required List<String> categories,
    required int targetWordCount,
    required int outsideVocabularyPercent,
  }) async {
    final provider = await settings.getProvider();
    if (provider == null) {
      throw const AiProviderException('No AI provider selected.');
    }
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();
    final vocabulary = selectVocabulary(
      availableVocabulary,
      targetWordCount: targetWordCount,
      outsideVocabularyPercent: outsideVocabularyPercent,
    );
    final pairs =
        vocabulary
            .map(
              (item) => {'source': item.word, 'translation': item.translation},
            )
            .toList();
    final data = await _generateJson('''
Write a coherent short story and a faithful translation.

Requirements:
- Source language: $sourceLanguage.
- Translation language: $translationLanguage.
- Aim for approximately $targetWordCount words in the source story.
- Aim for approximately $outsideVocabularyPercent% distinct content vocabulary outside the supplied list.
- Use as many supplied entries as naturally possible, preserving every used entry exactly as written.
- A supplied entry may be a complete phrase or sentence; keep it whole.
- Both texts must express the same story.
- Return exactly: {"source":"...","translation":"..."}

Vocabulary pairs:
${jsonEncode(pairs)}
''');
    final source = data['source'] as String?;
    final translation = data['translation'] as String?;
    if (source == null ||
        translation == null ||
        source.isEmpty ||
        translation.isEmpty) {
      throw const FormatException('The generated text response is incomplete.');
    }
    final matchedEntries =
        <VocabularyEntry>{
          ...VocabularyMatcher.findMatches(
            source,
            availableVocabulary,
            translated: false,
          ).map((match) => match.entry),
          ...VocabularyMatcher.findMatches(
            translation,
            availableVocabulary,
            translated: true,
          ).map((match) => match.entry),
        }.toList();
    return GeneratedText(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      source: source,
      translation: translation,
      createdAt: DateTime.now(),
      categories: List.unmodifiable(categories),
      targetWordCount: targetWordCount,
      outsideVocabularyPercent: outsideVocabularyPercent,
      provider: provider,
      vocabulary: List.unmodifiable(matchedEntries),
    );
  }

  Future<Map<String, dynamic>> _generateJson(String prompt) async {
    final provider = await settings.getProvider();
    if (provider == null) {
      throw const AiProviderException('No AI provider selected.');
    }
    final client = await (_clientFactory ?? AiProviderClientFactory(settings))
        .create(provider);
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final raw = await client.generate(
          attempt == 0
              ? prompt
              : '$prompt\nYour previous response was invalid. Return only valid JSON.',
        );
        return _decodeJsonObject(raw);
      } catch (error) {
        lastError = error;
        if (error is AiProviderException) rethrow;
      }
    }
    throw FormatException('The AI provider returned invalid JSON: $lastError');
  }

  static Map<String, dynamic> _decodeJsonObject(String raw) {
    var value = raw.trim();
    if (value.startsWith('```')) {
      value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      value = value.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Missing JSON object.');
    }
    return jsonDecode(value.substring(start, end + 1)) as Map<String, dynamic>;
  }

  static List<VocabularyEntry> selectVocabulary(
    List<VocabularyEntry> available, {
    required int targetWordCount,
    required int outsideVocabularyPercent,
    Random? random,
  }) {
    final shuffled = List<VocabularyEntry>.from(available)
      ..shuffle(random ?? Random());
    final knownBudget = max(
      1,
      (targetWordCount * (100 - outsideVocabularyPercent) / 100).round(),
    );
    final selected = <VocabularyEntry>[];
    var used = 0;
    for (final entry in shuffled) {
      final units = estimateWordCount(entry.word);
      if (selected.isNotEmpty && used + units > knownBudget) continue;
      selected.add(entry);
      used += units;
      if (used >= knownBudget) break;
    }
    if (selected.isEmpty && shuffled.isNotEmpty) selected.add(shuffled.first);
    return selected;
  }

  static int estimateWordCount(String text) {
    final cjk =
        RegExp(
          r'[\u3400-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]',
        ).allMatches(text).length;
    final withoutCjk = text.replaceAll(
      RegExp(r'[\u3400-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]'),
      ' ',
    );
    final words =
        RegExp(
          r"[A-Za-zÀ-ÖØ-öø-ÿĀ-žА-Яа-я0-9]+(?:['’\-][A-Za-zÀ-ÖØ-öø-ÿĀ-žА-Яа-я0-9]+)*",
        ).allMatches(withoutCjk).length;
    return max(1, cjk + words);
  }
}
