import 'dart:convert';
import 'dart:math';

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

class AiGenerationService {
  AiGenerationService({
    AiSettingsService? settings,
    AiProviderClientFactory? clientFactory,
  }) : settings = settings ?? AiSettingsService(),
       _clientFactory = clientFactory;

  static const analysisOutputTokens = 4000;
  static const textOutputTokens = 8000;
  static const annotationOutputTokens = 4000;

  final AiSettingsService settings;
  final AiProviderClientFactory? _clientFactory;

  Future<BilingualSentence> generateSentence(VocabularyEntry entry) async {
    final provider = await _requireProvider();
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();
    final data = await _generateJson(
      provider: provider,
      maxOutputTokens: analysisOutputTokens,
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
    final corpusBatches = batchCorpus(availableVocabulary);
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
        maxOutputTokens: analysisOutputTokens,
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
      maxOutputTokens: textOutputTokens,
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
      final data = await _generateJson(
        provider: provider,
        maxOutputTokens: annotationOutputTokens,
        cancellationToken: cancellationToken,
        prompt: '''
Segment the exact text below in order. Preserve every character exactly once.

Requirements:
- Text language: $textLanguage.
- Contextual translations must be in $translationLanguage.
- Emit every lexical word/token as its own segment with isWord true.
- Whitespace, punctuation, and standalone symbols must be separate isWord false segments.
- For each word, provide learner-friendly pronunciation (pinyin, romaji, standard transliteration, or IPA as appropriate) and its concise contextual translation.
- surface values concatenated in order must reconstruct the input exactly.
- Return exactly: {"segments":[{"surface":"...","isWord":true,"pronunciation":"...","contextualTranslation":"..."}]}

Exact input text:
${jsonEncode(chunk)}
''',
        validate: (data) => _validateAnnotation(data, chunk),
      );
      var localOffset = 0;
      for (final segment
          in (data['segments'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final surface = segment['surface'] as String;
        if (segment['isWord'] == true) {
          annotations.add(
            WordAnnotation(
              start: globalOffset + localOffset,
              end: globalOffset + localOffset + surface.length,
              surface: surface,
              pronunciation: segment['pronunciation'] as String,
              contextualTranslation: segment['contextualTranslation'] as String,
            ),
          );
        }
        localOffset += surface.length;
      }
      globalOffset += chunk.length;
    }
    return annotations;
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

  static void _validateAnnotation(Map<String, dynamic> data, String text) {
    final segments = data['segments'];
    if (segments is! List || segments.isEmpty) {
      throw const FormatException('Missing annotation segments.');
    }
    final reconstructed = StringBuffer();
    for (final raw in segments) {
      if (raw is! Map<String, dynamic> ||
          raw['surface'] is! String ||
          raw['isWord'] is! bool) {
        throw const FormatException('Invalid annotation segment.');
      }
      final surface = raw['surface'] as String;
      if (surface.isEmpty) {
        throw const FormatException('Annotation segments cannot be empty.');
      }
      reconstructed.write(surface);
      if (raw['isWord'] == true) {
        if ((raw['pronunciation'] is! String) ||
            (raw['pronunciation'] as String).trim().isEmpty ||
            (raw['contextualTranslation'] is! String) ||
            (raw['contextualTranslation'] as String).trim().isEmpty) {
          throw const FormatException('A word annotation is incomplete.');
        }
      } else if (_containsLexicalText(surface)) {
        throw const FormatException('A lexical token was left unannotated.');
      }
    }
    if (reconstructed.toString() != text) {
      throw const FormatException(
        'Annotation segments do not reconstruct the generated text.',
      );
    }
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

  static bool _containsLexicalText(String text) => RegExp(
    r'[A-Za-zÀ-ÖØ-öø-ÿĀ-žΑ-ωА-Яа-я\u0590-\u05FF\u0600-\u06FF\u3400-\u9FFF\u3040-\u30FF\uAC00-\uD7AF0-9]',
  ).hasMatch(text);

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
