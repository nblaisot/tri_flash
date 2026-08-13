import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';

enum AiGenerationStage {
  analyzingCorpus,
  generatingText,
  annotatingSource,
  annotatingTranslation,
  saving,
}

class AiGenerationProgress {
  const AiGenerationProgress(this.stage, {this.current, this.total});

  final AiGenerationStage stage;
  final int? current;
  final int? total;
}

typedef AiProgressCallback = void Function(AiGenerationProgress progress);

class AiAnnotationException implements Exception {
  const AiAnnotationException({
    required this.stage,
    required this.chunk,
    required this.totalChunks,
  });

  final AiGenerationStage stage;
  final int chunk;
  final int totalChunks;

  @override
  String toString() =>
      'AI annotation failed for ${stage == AiGenerationStage.annotatingSource ? 'the original' : 'the translation'} '
      '(chunk $chunk/$totalChunks) after two attempts. Nothing was saved.';
}

enum _AnnotationFailure {
  malformedResponse,
  missingDetails,
  nonLexicalSurface,
  alteredSurface,
  duplicatedOrOutOfOrder,
  omittedOrOutOfOrder,
  omittedWord,
}

class _AnnotationValidationException implements Exception {
  const _AnnotationValidationException(this.failure, this.offset);

  final _AnnotationFailure failure;
  final int offset;

  String get repairHint => switch (failure) {
    _AnnotationFailure.malformedResponse =>
      'Return exactly the requested JSON object with a words array.',
    _AnnotationFailure.missingDetails =>
      'Every word must have a non-empty surface, pronunciation, and contextualTranslation.',
    _AnnotationFailure.nonLexicalSurface =>
      'Return lexical word surfaces only. Exclude adjacent punctuation, whitespace, and standalone symbols.',
    _AnnotationFailure.alteredSurface =>
      'A returned surface was altered or invented. Copy every surface exactly from the input without normalizing or rewriting characters.',
    _AnnotationFailure.duplicatedOrOutOfOrder =>
      'A returned word was duplicated or placed out of order. Include every lexical word exactly once and in its original order.',
    _AnnotationFailure.omittedOrOutOfOrder =>
      'A lexical word before the next returned surface was omitted or the words are out of order. Include every lexical word exactly once and in order.',
    _AnnotationFailure.omittedWord =>
      'One or more lexical words at the end were omitted. Include every lexical word exactly once and in order.',
  };
}

class AiGenerationService {
  AiGenerationService({
    AiSettingsService? settings,
    AiProviderClientFactory? clientFactory,
  }) : settings = settings ?? AiSettingsService(),
       _clientFactory = clientFactory;

  static const analysisOutputTokens = 4000;
  static const textOutputTokens = 8000;
  static const annotationOutputTokens = 4000;

  static const onDeviceAnalysisOutputTokens = 2048;
  static const onDeviceTextOutputTokens = 4096;
  static const onDeviceAnnotationOutputTokens = 2048;

  static const onDeviceMaxCorpusEntries = 50;
  static const onDeviceMaxCorpusCharacters = 3000;

  int _analysisOutputTokens(AiProviderType provider) =>
      provider == AiProviderType.onDevice
          ? onDeviceAnalysisOutputTokens
          : analysisOutputTokens;

  int _textOutputTokens(AiProviderType provider) =>
      provider == AiProviderType.onDevice
          ? onDeviceTextOutputTokens
          : textOutputTokens;

  int _annotationOutputTokens(AiProviderType provider) =>
      provider == AiProviderType.onDevice
          ? onDeviceAnnotationOutputTokens
          : annotationOutputTokens;

  List<List<VocabularyEntry>> _corpusBatches(
    List<VocabularyEntry> entries,
    AiProviderType provider,
  ) =>
      batchCorpus(
        entries,
        maxEntries:
            provider == AiProviderType.onDevice
                ? onDeviceMaxCorpusEntries
                : 200,
        maxCharacters:
            provider == AiProviderType.onDevice
                ? onDeviceMaxCorpusCharacters
                : 12000,
      );

  final AiSettingsService settings;
  final AiProviderClientFactory? _clientFactory;

  Future<BilingualSentence> generateSentence(VocabularyEntry entry) async {
    final provider = await _requireProvider();
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();
    final data = await _generateJson(
      provider: provider,
      maxOutputTokens: _analysisOutputTokens(provider),
      prompt: '''
Create one natural example sentence and its faithful translation.

Requirements:
- The source sentence language is $sourceLanguage and must contain this exact vocabulary form: ${jsonEncode(entry.word)}.
- The translated sentence language is $translationLanguage and must contain this exact translated form: ${jsonEncode(entry.translation)}.
- Keep both sentences concise and semantically equivalent.
- Return exactly: {"source":"...","translation":"..."}
''',
      validate: (data) {
        _requiredString(data, 'source');
        _requiredString(data, 'translation');
      },
    );
    return BilingualSentence(
      source: data['source'] as String,
      translation: data['translation'] as String,
    );
  }

  Future<GeneratedText> generateText({
    required List<VocabularyEntry> availableVocabulary,
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

    final token = cancellationToken ?? AiCancellationToken();
    final provider = await _requireProvider();
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();
    final corpusBatches = _corpusBatches(availableVocabulary, provider);
    final analyses = <Map<String, dynamic>>[];

    for (var index = 0; index < corpusBatches.length; index++) {
      token.throwIfCancelled();
      onProgress?.call(
        AiGenerationProgress(
          AiGenerationStage.analyzingCorpus,
          current: index + 1,
          total: corpusBatches.length,
        ),
      );
      final batch = corpusBatches[index];
      final input = [
        for (final entry in batch)
          {
            'id': entry.id.toString(),
            'source': entry.word,
            'translation': entry.translation,
            'category': entry.category,
          },
      ];
      final expectedIds = input.map((item) => item['id']!).toSet();
      final data = await _generateJson(
        provider: provider,
        maxOutputTokens: _analysisOutputTokens(provider),
        cancellationToken: token,
        prompt: '''
Analyze every vocabulary entry below for use in a new language-learning text.

For each input entry, return exactly one result with the same id:
- kind is "lexical" for a word or reusable short phrase, or "structure" for a sentence-like example.
- lexicalTargets contains concise reusable words/idioms represented by the entry.
- grammarStructures contains abstract reusable grammar or syntax patterns illustrated by sentence-like entries. Never copy a full example sentence into this field.
- Do not omit, merge, or invent ids.

Return exactly:
{"entries":[{"id":"...","kind":"lexical|structure","lexicalTargets":["..."],"grammarStructures":["..."]}]}

Source language: $sourceLanguage
Translation language: $translationLanguage
Entries:
${jsonEncode(input)}
''',
        validate: (data) => _validateAnalysis(data, expectedIds),
      );
      analyses.addAll(
        (data['entries'] as List<dynamic>).cast<Map<String, dynamic>>(),
      );
    }

    token.throwIfCancelled();
    onProgress?.call(
      const AiGenerationProgress(AiGenerationStage.generatingText),
    );
    final forbidden = <String>[];
    for (final analysis in analyses) {
      if (analysis['kind'] == 'structure') {
        final id = analysis['id'] as String;
        final original = availableVocabulary.firstWhere(
          (entry) => entry.id.toString() == id,
        );
        forbidden.add(original.word);
        forbidden.add(original.translation);
      }
    }
    final bilingual = await _generateJson(
      provider: provider,
      maxOutputTokens: _textOutputTokens(provider),
      cancellationToken: token,
      prompt: '''
Write a varied, coherent passage and a faithful translation using the complete analyzed corpus below.

Requirements:
- Source language: $sourceLanguage.
- Translation language: $translationLanguage.
- The source passage should contain approximately $targetWordCount lexical words. The translation may have its natural length.
- Aim for approximately $outsideVocabularyPercent% content vocabulary outside the supplied lexical targets.
- Use the lexical targets as broadly and naturally as possible; this is best effort and the passage need not contain every target.
- Reuse the extracted grammar structures naturally.
- Do not reproduce any sentence-like source entry or its translation verbatim.
- Both texts must express the same passage.
- Return exactly: {"source":"...","translation":"..."}

Complete corpus analysis:
${jsonEncode(analyses)}

Forbidden verbatim sentences:
${jsonEncode(forbidden)}
''',
      validate: (data) {
        _requiredString(data, 'source');
        _requiredString(data, 'translation');
      },
    );
    final source = bilingual['source'] as String;
    final translation = bilingual['translation'] as String;

    final sourceAnnotations = await _annotateText(
      text: source,
      textLanguage: sourceLanguage,
      translationLanguage: translationLanguage,
      provider: provider,
      cancellationToken: token,
      stage: AiGenerationStage.annotatingSource,
      onProgress: onProgress,
    );
    final translationAnnotations = await _annotateText(
      text: translation,
      textLanguage: translationLanguage,
      translationLanguage: sourceLanguage,
      provider: provider,
      cancellationToken: token,
      stage: AiGenerationStage.annotatingTranslation,
      onProgress: onProgress,
    );
    token.throwIfCancelled();
    onProgress?.call(const AiGenerationProgress(AiGenerationStage.saving));

    return GeneratedText(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      source: source,
      translation: translation,
      createdAt: DateTime.now(),
      categories: List.unmodifiable(categories),
      targetWordCount: targetWordCount,
      outsideVocabularyPercent: outsideVocabularyPercent,
      provider: provider,
      sourceAnnotations: List.unmodifiable(sourceAnnotations),
      translationAnnotations: List.unmodifiable(translationAnnotations),
    );
  }

  Future<List<WordAnnotation>> _annotateText({
    required String text,
    required String textLanguage,
    required String translationLanguage,
    required AiProviderType provider,
    required AiCancellationToken cancellationToken,
    required AiGenerationStage stage,
    AiProgressCallback? onProgress,
  }) async {
    final chunks = chunkText(text);
    final annotations = <WordAnnotation>[];
    var globalOffset = 0;
    for (var index = 0; index < chunks.length; index++) {
      cancellationToken.throwIfCancelled();
      onProgress?.call(
        AiGenerationProgress(stage, current: index + 1, total: chunks.length),
      );
      final chunk = chunks[index];
      final chunkAnnotations = await _generateAnnotations(
        text: chunk,
        globalOffset: globalOffset,
        chunk: index + 1,
        totalChunks: chunks.length,
        stage: stage,
        textLanguage: textLanguage,
        translationLanguage: translationLanguage,
        provider: provider,
        cancellationToken: cancellationToken,
      );
      annotations.addAll(chunkAnnotations);
      globalOffset += chunk.length;
    }
    return annotations;
  }

  Future<List<WordAnnotation>> _generateAnnotations({
    required String text,
    required int globalOffset,
    required int chunk,
    required int totalChunks,
    required AiGenerationStage stage,
    required String textLanguage,
    required String translationLanguage,
    required AiProviderType provider,
    required AiCancellationToken cancellationToken,
  }) async {
    final prompt = '''
Identify every lexical word in the exact text below, in its original order.

Requirements:
- Text language: $textLanguage.
- Contextual translations must be in $translationLanguage.
- Return every lexical word exactly once and in order.
- Copy each surface exactly from the input. Do not normalize, correct, or rewrite any character.
- Do not return whitespace, adjacent punctuation, or standalone symbols.
- A lexical surface may contain internal apostrophes, hyphens, or combining marks when they are part of the displayed word.
- For each word, provide learner-friendly pronunciation (pinyin, romaji, standard transliteration, or IPA as appropriate) and its concise contextual translation.
- Return exactly: {"words":[{"surface":"...","pronunciation":"...","contextualTranslation":"..."}]}

Exact input text:
${jsonEncode(text)}
''';
    _AnnotationValidationException? lastValidation;
    for (var attempt = 0; attempt < 2; attempt++) {
      cancellationToken.throwIfCancelled();
      try {
        final client = await (_clientFactory ??
                AiProviderClientFactory(settings))
            .create(provider);
        final raw = await client.generate(
          attempt == 0
              ? prompt
              : '$prompt\nThe previous annotation was invalid. ${lastValidation?.repairHint ?? _AnnotationValidationException(_AnnotationFailure.malformedResponse, 0).repairHint} Return only complete valid JSON.',
          maxOutputTokens: _annotationOutputTokens(provider),
          cancellationToken: cancellationToken,
        );
        final data = _decodeJsonObject(raw);
        final words = data['words'];
        if (words is! List) {
          throw const _AnnotationValidationException(
            _AnnotationFailure.malformedResponse,
            0,
          );
        }
        return alignAnnotationWords(text, words, globalOffset: globalOffset);
      } on AiGenerationCancelled {
        rethrow;
      } on AiProviderException catch (error) {
        if (!error.isTransient || attempt == 1) rethrow;
      } on _AnnotationValidationException catch (error) {
        lastValidation = error;
      } catch (_) {
        lastValidation = const _AnnotationValidationException(
          _AnnotationFailure.malformedResponse,
          0,
        );
      }
    }
    final failure =
        lastValidation ??
        const _AnnotationValidationException(
          _AnnotationFailure.malformedResponse,
          0,
        );
    if (kDebugMode) {
      debugPrint(
        'AI annotation validation failed: stage=${stage.name} '
        'chunk=$chunk/$totalChunks category=${failure.failure.name} '
        'offset=${failure.offset}',
      );
    }
    throw AiAnnotationException(
      stage: stage,
      chunk: chunk,
      totalChunks: totalChunks,
    );
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
      } on AiProviderException catch (error) {
        lastError = error;
        if (!error.isTransient) rethrow;
      } catch (error) {
        lastError = error;
      }
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

  static void _validateAnalysis(
    Map<String, dynamic> data,
    Set<String> expectedIds,
  ) {
    final entries = data['entries'];
    if (entries is! List) throw const FormatException('Missing entries.');
    final ids = <String>{};
    for (final raw in entries) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid analysis entry.');
      }
      final id = raw['id'];
      final kind = raw['kind'];
      if (id is! String || !expectedIds.contains(id) || !ids.add(id)) {
        throw const FormatException(
          'Analysis contains missing or duplicate ids.',
        );
      }
      if (kind != 'lexical' && kind != 'structure') {
        throw const FormatException('Invalid analysis kind.');
      }
      if (raw['lexicalTargets'] is! List || raw['grammarStructures'] is! List) {
        throw const FormatException('Incomplete analysis entry.');
      }
    }
    if (ids.length != expectedIds.length || !ids.containsAll(expectedIds)) {
      throw const FormatException('Not every corpus entry was analyzed.');
    }
  }

  @visibleForTesting
  static List<WordAnnotation> alignAnnotationWords(
    String text,
    List<dynamic> words, {
    int globalOffset = 0,
  }) {
    final annotations = <WordAnnotation>[];
    var cursor = 0;
    for (final raw in words) {
      if (raw is! Map<String, dynamic>) {
        throw _AnnotationValidationException(
          _AnnotationFailure.malformedResponse,
          cursor,
        );
      }
      final surface = raw['surface'];
      final pronunciation = raw['pronunciation'];
      final translation = raw['contextualTranslation'];
      if (surface is! String ||
          surface.isEmpty ||
          pronunciation is! String ||
          pronunciation.trim().isEmpty ||
          translation is! String ||
          translation.trim().isEmpty) {
        throw _AnnotationValidationException(
          _AnnotationFailure.missingDetails,
          cursor,
        );
      }
      if (!_isLexicalSurface(surface)) {
        throw _AnnotationValidationException(
          _AnnotationFailure.nonLexicalSurface,
          cursor,
        );
      }
      final start = text.indexOf(surface, cursor);
      if (start < 0) {
        throw _AnnotationValidationException(
          text.contains(surface)
              ? _AnnotationFailure.duplicatedOrOutOfOrder
              : _AnnotationFailure.alteredSurface,
          cursor,
        );
      }
      if (_containsLexicalText(text.substring(cursor, start))) {
        throw _AnnotationValidationException(
          _AnnotationFailure.omittedOrOutOfOrder,
          cursor,
        );
      }
      final end = start + surface.length;
      annotations.add(
        WordAnnotation(
          start: globalOffset + start,
          end: globalOffset + end,
          surface: text.substring(start, end),
          pronunciation: pronunciation,
          contextualTranslation: translation,
        ),
      );
      cursor = end;
    }
    if (_containsLexicalText(text.substring(cursor))) {
      throw _AnnotationValidationException(
        _AnnotationFailure.omittedWord,
        cursor,
      );
    }
    return annotations;
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

  static List<List<VocabularyEntry>> batchCorpus(
    List<VocabularyEntry> entries, {
    int maxEntries = 200,
    int maxCharacters = 12000,
  }) {
    final batches = <List<VocabularyEntry>>[];
    var current = <VocabularyEntry>[];
    var characters = 0;
    for (final entry in entries) {
      final size =
          entry.word.length + entry.translation.length + entry.category.length;
      if (current.isNotEmpty &&
          (current.length >= maxEntries || characters + size > maxCharacters)) {
        batches.add(current);
        current = <VocabularyEntry>[];
        characters = 0;
      }
      current.add(entry);
      characters += size;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
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

  static bool _containsLexicalText(String text) =>
      text.runes.any(_isLexicalRune);

  static bool _isLexicalSurface(String surface) {
    final runes = surface.runes;
    if (runes.isEmpty) return false;
    return _isLexicalRune(runes.first) && _isLexicalRune(runes.last);
  }

  static bool _isLexicalRune(int rune) {
    if (rune == 0xD7 || rune == 0xF7 || rune == 0x37E || rune == 0x387) {
      return false;
    }
    return (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xC0 && rune <= 0x2AF) ||
        (rune >= 0x300 && rune <= 0x36F) ||
        (rune >= 0x370 && rune <= 0x52F) ||
        (rune >= 0x591 && rune <= 0x5BD) ||
        rune == 0x5BF ||
        (rune >= 0x5C1 && rune <= 0x5C2) ||
        (rune >= 0x5C4 && rune <= 0x5C5) ||
        rune == 0x5C7 ||
        (rune >= 0x5D0 && rune <= 0x5EA) ||
        (rune >= 0x610 && rune <= 0x61A) ||
        (rune >= 0x620 && rune <= 0x63F) ||
        (rune >= 0x641 && rune <= 0x65F) ||
        (rune >= 0x660 && rune <= 0x669) ||
        (rune >= 0x670 && rune <= 0x6D3) ||
        (rune >= 0x6D5 && rune <= 0x6ED) ||
        (rune >= 0x6EE && rune <= 0x6FC) ||
        (rune >= 0x6F0 && rune <= 0x6F9) ||
        (rune >= 0x3041 && rune <= 0x3096) ||
        (rune >= 0x30A1 && rune <= 0x30FA) ||
        rune == 0x30FC ||
        (rune >= 0x3400 && rune <= 0x9FFF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF) ||
        (rune >= 0xFB1D && rune <= 0xFB4F);
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
