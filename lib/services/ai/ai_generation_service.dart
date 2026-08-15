import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';

enum AiGenerationStage {
  generatingText,
  annotatingSource,
  saving,
}

class AiGenerationProgress {
  const AiGenerationProgress(this.stage, {this.current, this.total});

  final AiGenerationStage stage;
  final int? current;
  final int? total;
}

typedef AiProgressCallback = void Function(AiGenerationProgress progress);

class AiCorpusTooLargeException implements Exception {
  const AiCorpusTooLargeException();

  @override
  String toString() =>
      'Corpus is too large for one generation request. Select fewer categories and try again.';
}

class AiGenerationService {
  AiGenerationService({
    AiSettingsService? settings,
    AiProviderClientFactory? clientFactory,
  }) : settings = settings ?? AiSettingsService(),
       _clientFactory = clientFactory;

  /// Short JSON responses (e.g. single example sentence).
  static const sentenceOutputTokens = 4000;
  static const textOutputTokens = 8000;

  static const onDeviceSentenceOutputTokens = 2048;
  static const onDeviceTextOutputTokens = 4096;

  static const maxCorpusEntries = 800;
  static const maxCorpusCharacters = 100000;

  int _sentenceOutputTokens(AiProviderType provider) =>
      provider == AiProviderType.onDevice
          ? onDeviceSentenceOutputTokens
          : sentenceOutputTokens;

  int _textOutputTokens(AiProviderType provider) =>
      provider == AiProviderType.onDevice
          ? onDeviceTextOutputTokens
          : textOutputTokens;

  final AiSettingsService settings;
  final AiProviderClientFactory? _clientFactory;

  Future<BilingualSentence> generateSentence(VocabularyEntry entry) async {
    final provider = await _requireProvider();
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();
    final data = await _generateJson(
      provider: provider,
      maxOutputTokens: _sentenceOutputTokens(provider),
      prompt: '''
Create one natural example sentence and its faithful translation.

Requirements:
- The source sentence language is $sourceLanguage and must contain this exact vocabulary form: ${jsonEncode(entry.word)}.
- The translated sentence language is $translationLanguage and must contain this exact translated form: ${jsonEncode(entry.translation)}.
- Also provide a learner-friendly pronunciation line for the full source sentence (pinyin, romaji, or standard transliteration as appropriate for $sourceLanguage).
- Keep both sentences concise and semantically equivalent.
- Return exactly: {"source":"...","transcription":"...","translation":"..."}
''',
      validate: (data) {
        _requiredString(data, 'source');
        _requiredString(data, 'transcription');
        _requiredString(data, 'translation');
      },
    );
    return BilingualSentence(
      source: data['source'] as String,
      transcription: data['transcription'] as String,
      translation: data['translation'] as String,
    );
  }

  Future<GeneratedText> generateText({
    required List<VocabularyEntry> availableVocabulary,
    required List<VocabularyEntry> annotationVocabulary,
    required List<String> categories,
    required int targetWordCount,
    required int outsideVocabularyPercent,
    AiCancellationToken? cancellationToken,
    AiProgressCallback? onProgress,
  }) async {
    if (targetWordCount < 20 || targetWordCount > 500) {
      throw const FormatException('Target word count must be from 20 to 500.');
    }
    if (outsideVocabularyPercent < 0 || outsideVocabularyPercent > 50) {
      throw const FormatException(
        'Outside-vocabulary percentage must be from 0 to 50.',
      );
    }
    if (availableVocabulary.isEmpty) {
      throw const FormatException('At least one vocabulary entry is required.');
    }

    final corpusDump = [
      for (final entry in availableVocabulary)
        {
          'source': entry.word,
          'translation': entry.translation,
          'category': entry.category,
        },
    ];
    final corpusJson = jsonEncode(corpusDump);
    if (isCorpusTooLarge(
      entryCount: availableVocabulary.length,
      corpusJsonCharacters: corpusJson.length,
    )) {
      throw const AiCorpusTooLargeException();
    }

    final token = cancellationToken ?? AiCancellationToken();
    final provider = await _requireProvider();
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();

    token.throwIfCancelled();
    onProgress?.call(
      const AiGenerationProgress(AiGenerationStage.generatingText),
    );

    final bilingual = await _generateJson(
      provider: provider,
      maxOutputTokens: _textOutputTokens(provider),
      cancellationToken: token,
      prompt: '''
Write a varied, coherent passage and a faithful translation for language learning.

How to use the vocabulary dump below:
- Distinguish short reusable items (words or short phrases) from sentence-like example entries.
- Weave the words/phrases into the passage as broadly and naturally as possible (best effort; the passage need not contain every item).
- For sentence-like entries, infer the grammar or syntax patterns they illustrate and reuse those patterns naturally. Never copy any sentence-like source or its translation verbatim.
- Aim for approximately $outsideVocabularyPercent% content vocabulary outside the supplied dump.

Requirements:
- Source language: $sourceLanguage.
- Translation language: $translationLanguage.
- The source passage should contain approximately $targetWordCount lexical words. The translation may have its natural length.
- Both texts must express the same passage.
- Also invent a short bilingual title for the passage: title in $sourceLanguage and titleTranslation in $translationLanguage. Keep each title concise (a few words).
- Return exactly: {"title":"...","titleTranslation":"...","source":"...","translation":"..."}

Vocabulary dump (words/phrases and sentence-like examples):
$corpusJson
''',
      validate: (data) {
        _requiredString(data, 'title');
        _requiredString(data, 'titleTranslation');
        _requiredString(data, 'source');
        _requiredString(data, 'translation');
      },
    );
    final title = bilingual['title'] as String;
    final titleTranslation = bilingual['titleTranslation'] as String;
    final source = bilingual['source'] as String;
    final translation = bilingual['translation'] as String;

    token.throwIfCancelled();
    onProgress?.call(
      const AiGenerationProgress(AiGenerationStage.annotatingSource),
    );
    final sourceAnnotations = annotateWithVocabulary(
      source,
      annotationVocabulary,
    );
    token.throwIfCancelled();
    onProgress?.call(const AiGenerationProgress(AiGenerationStage.saving));

    return GeneratedText(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
      titleTranslation: titleTranslation.trim(),
      source: source,
      translation: translation,
      createdAt: DateTime.now(),
      categories: List.unmodifiable(categories),
      targetWordCount: targetWordCount,
      outsideVocabularyPercent: outsideVocabularyPercent,
      provider: provider,
      sourceAnnotations: List.unmodifiable(sourceAnnotations),
      translationAnnotations: const [],
    );
  }

  @visibleForTesting
  static bool isCorpusTooLarge({
    required int entryCount,
    required int corpusJsonCharacters,
  }) =>
      entryCount > maxCorpusEntries ||
      corpusJsonCharacters > maxCorpusCharacters;

  @visibleForTesting
  static bool isCorpusSizeProviderError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('context_length') ||
        message.contains('context length') ||
        message.contains('maximum context') ||
        message.contains('max context') ||
        message.contains('too many tokens') ||
        message.contains('token limit') ||
        message.contains('prompt is too long') ||
        message.contains('prompt too long') ||
        message.contains('request too large') ||
        message.contains('payload too large') ||
        RegExp(r'\b413\b').hasMatch(message) ||
        (message.contains('400') &&
            (message.contains('token') || message.contains('context')));
  }

  @visibleForTesting
  static Map<String, VocabularyEntry> buildVocabularyIndex(
    List<VocabularyEntry> vocabulary,
  ) {
    final index = <String, VocabularyEntry>{};
    for (final entry in vocabulary) {
      if (entry.word.isEmpty) continue;
      final existing = index[entry.word];
      if (existing == null) {
        index[entry.word] = entry;
      } else if (entry.isActive && !existing.isActive) {
        index[entry.word] = entry;
      }
    }
    return index;
  }

  @visibleForTesting
  static List<WordAnnotation> annotateWithVocabulary(
    String text,
    List<VocabularyEntry> vocabulary,
  ) {
    if (text.isEmpty || vocabulary.isEmpty) return const [];

    final index = buildVocabularyIndex(vocabulary);
    if (index.isEmpty) return const [];

    final maxKeyLength = index.keys.fold<int>(
      0,
      (max, key) => key.length > max ? key.length : max,
    );
    final annotations = <WordAnnotation>[];
    var offset = 0;
    while (offset < text.length) {
      VocabularyEntry? match;
      var matchLength = 0;
      final maxTry = min(maxKeyLength, text.length - offset);
      for (var length = maxTry; length >= 1; length--) {
        final candidate = text.substring(offset, offset + length);
        final entry = index[candidate];
        if (entry != null) {
          match = entry;
          matchLength = length;
          break;
        }
      }
      if (match != null && matchLength > 0) {
        annotations.add(
          WordAnnotation(
            start: offset,
            end: offset + matchLength,
            surface: text.substring(offset, offset + matchLength),
            pronunciation: match.transcription,
            contextualTranslation: match.translation,
          ),
        );
        offset += matchLength;
      } else {
        offset = _nextRuneStart(text, offset);
      }
    }
    return annotations;
  }

  static int _nextRuneStart(String text, int offset) {
    if (offset >= text.length) return offset;
    final unit = text.codeUnitAt(offset);
    if (offset + 1 < text.length &&
        unit >= 0xD800 &&
        unit <= 0xDBFF &&
        text.codeUnitAt(offset + 1) >= 0xDC00 &&
        text.codeUnitAt(offset + 1) <= 0xDFFF) {
      return offset + 2;
    }
    return offset + 1;
  }

  Future<Map<String, dynamic>> _generateJson({
    required AiProviderType provider,
    required String prompt,
    required int maxOutputTokens,
    required void Function(Map<String, dynamic>) validate,
    AiCancellationToken? cancellationToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        final client = await (_clientFactory ??
                AiProviderClientFactory(settings))
            .create(provider);
        final raw = await client.generate(
          attempt == 0
              ? prompt
              : '$prompt\nThe previous response was invalid or incomplete. Return only complete valid JSON.',
          maxOutputTokens: maxOutputTokens,
          cancellationToken: cancellationToken,
        );
        final data = _decodeJsonObject(raw);
        validate(data);
        return data;
      } on AiGenerationCancelled {
        rethrow;
      } on AiCorpusTooLargeException {
        rethrow;
      } on AiProviderException catch (error) {
        if (isCorpusSizeProviderError(error)) {
          throw const AiCorpusTooLargeException();
        }
        lastError = error;
        if (!error.isTransient) rethrow;
      } catch (error) {
        if (isCorpusSizeProviderError(error)) {
          throw const AiCorpusTooLargeException();
        }
        lastError = error;
      }
    }
    if (lastError != null && isCorpusSizeProviderError(lastError)) {
      throw const AiCorpusTooLargeException();
    }
    throw FormatException('The AI provider returned invalid data: $lastError');
  }

  Future<AiProviderType> _requireProvider() async {
    final provider = await settings.getProvider();
    if (provider == null) {
      throw const AiProviderException('No AI provider selected.');
    }
    return provider;
  }

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing $key.');
    }
    return value;
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

  static List<String> chunkText(
    String text, {
    int maxLexicalUnits = 80,
    int maxCharacters = 600,
  }) {
    if (text.isEmpty) return const [];
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = min(start + maxCharacters, text.length);
      while (end > start + 1 &&
          estimateWordCount(text.substring(start, end)) > maxLexicalUnits) {
        end--;
      }
      end = _avoidSplittingSurrogatePair(text, end);
      if (end < text.length) {
        final candidate = text.substring(start, end);
        final boundary = _lastBoundary(candidate);
        if (boundary > 0) end = start + boundary;
      }
      if (end <= start) end = min(start + 1, text.length);
      chunks.add(text.substring(start, end));
      start = end;
    }
    return chunks;
  }

  static int _lastBoundary(String value) {
    for (var index = value.length - 1; index >= 0; index--) {
      if (RegExp(r'[\s.!?。！？]').hasMatch(value[index])) return index + 1;
    }
    return 0;
  }

  static int _avoidSplittingSurrogatePair(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return offset;
    final previous = text.codeUnitAt(offset - 1);
    final next = text.codeUnitAt(offset);
    final previousIsHighSurrogate = previous >= 0xD800 && previous <= 0xDBFF;
    final nextIsLowSurrogate = next >= 0xDC00 && next <= 0xDFFF;
    return previousIsHighSurrogate && nextIsLowSurrogate ? offset - 1 : offset;
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
          r"[A-Za-zÀ-ÖØ-öø-ÿĀ-žΑ-ωА-Яа-я\u0590-\u05FF\u0600-\u06FF0-9]+(?:['’\-][A-Za-zÀ-ÖØ-öø-ÿĀ-žΑ-ωА-Яа-я\u0590-\u05FF\u0600-\u06FF0-9]+)*",
        ).allMatches(withoutCjk).length;
    return max(1, cjk + words);
  }
}
