import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';
import 'package:tri_flash/services/ai/on_device_ai_provider_client.dart';

enum AiGenerationStage {
  generatingText,
  generatingQuiz,
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
  static const quizOutputTokens = 8000;
  static const checkOutputTokens = 2000;

  static const onDeviceSentenceOutputTokens = 768;
  static const onDeviceTextOutputTokens = 1536;
  static const onDeviceQuizOutputTokens = 1280;
  static const onDeviceCheckOutputTokens = 512;

  static const onDeviceSafetyTokens = 256;
  static const onDeviceMaxInputTokens = 2800;
  static const onDevicePassageWordsPerBatch = 75;
  static const onDeviceQuizItemsPerBatch = 5;

  static const allowedQuizSentenceCounts = {5, 10, 15, 20};

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

  int _quizOutputTokens(AiProviderType provider) =>
      provider == AiProviderType.onDevice
          ? onDeviceQuizOutputTokens
          : quizOutputTokens;

  int _checkOutputTokens(AiProviderType provider) =>
      provider == AiProviderType.onDevice
          ? onDeviceCheckOutputTokens
          : checkOutputTokens;

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
      responseSchema: AiResponseSchema.bilingualSentence,
      languageCodes: _languageCodes(sourceLanguage, translationLanguage),
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

    if (provider == AiProviderType.onDevice) {
      return _generateLocalText(
        availableVocabulary: availableVocabulary,
        annotationVocabulary: annotationVocabulary,
        categories: categories,
        targetWordCount: targetWordCount,
        outsideVocabularyPercent: outsideVocabularyPercent,
        sourceLanguage: sourceLanguage,
        translationLanguage: translationLanguage,
        cancellationToken: token,
        onProgress: onProgress,
      );
    }

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
      responseSchema: AiResponseSchema.passageStart,
      languageCodes: _languageCodes(sourceLanguage, translationLanguage),
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

  Future<TranslationQuiz> generateTranslationQuiz({
    required List<VocabularyEntry> availableVocabulary,
    required List<String> categories,
    required int sentenceCount,
    required TranslationQuizDirection direction,
    AiCancellationToken? cancellationToken,
    AiProgressCallback? onProgress,
  }) async {
    if (!allowedQuizSentenceCounts.contains(sentenceCount)) {
      throw const FormatException(
        'Sentence count must be one of 5, 10, 15, or 20.',
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
      const AiGenerationProgress(AiGenerationStage.generatingQuiz),
    );

    if (provider == AiProviderType.onDevice) {
      return _generateLocalQuiz(
        availableVocabulary: availableVocabulary,
        categories: categories,
        sentenceCount: sentenceCount,
        direction: direction,
        sourceLanguage: sourceLanguage,
        translationLanguage: translationLanguage,
        cancellationToken: token,
        onProgress: onProgress,
      );
    }

    final data = await _generateJson(
      provider: provider,
      maxOutputTokens: _quizOutputTokens(provider),
      cancellationToken: token,
      prompt: '''
Create a translation quiz of exactly $sentenceCount bilingual sentence pairs for language learning.

How to use the vocabulary dump below:
- Distinguish short reusable items (words or short phrases) from sentence-like example entries.
- Weave the words/phrases into the quiz sentences as broadly and naturally as possible (best effort; not every item must appear).
- For sentence-like entries, infer the grammar or syntax patterns they illustrate and invent NEW sentences that reuse those patterns. Never copy any sentence-like source or its translation verbatim.
- Prefer sentences that are pedagogically useful: natural wording, clear meaning, and grammar that matches the corpus.

Requirements:
- Source language: $sourceLanguage.
- Translation language: $translationLanguage.
- Produce exactly $sentenceCount pairs.
- Each pair must express the same meaning in both languages.
- Vary topics and structures across the set.
- Return exactly: {"sentences":[{"source":"...","translation":"..."}, ...]}

Vocabulary dump (words/phrases and sentence-like examples):
$corpusJson
''',
      validate: (data) {
        final sentences = data['sentences'];
        if (sentences is! List || sentences.length != sentenceCount) {
          throw FormatException('Expected exactly $sentenceCount sentences.');
        }
        for (final item in sentences) {
          if (item is! Map) {
            throw const FormatException('Each sentence must be an object.');
          }
          final map = Map<String, dynamic>.from(item);
          _requiredString(map, 'source');
          _requiredString(map, 'translation');
        }
      },
      responseSchema: AiResponseSchema.quizBatch,
      languageCodes: _languageCodes(sourceLanguage, translationLanguage),
    );

    token.throwIfCancelled();
    final rawSentences = data['sentences'] as List<dynamic>;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final items = <TranslationQuizItem>[];
    for (var index = 0; index < rawSentences.length; index++) {
      final map = Map<String, dynamic>.from(rawSentences[index] as Map);
      items.add(
        TranslationQuizItem.fromBilingualPair(
          id: '${stamp}_$index',
          source: map['source'] as String,
          translation: map['translation'] as String,
          direction: direction,
        ),
      );
    }

    return TranslationQuiz(
      items: List.unmodifiable(items),
      categories: List.unmodifiable(categories),
      sentenceCount: sentenceCount,
      direction: direction,
      provider: provider,
    );
  }

  Future<TranslationCheckResult> checkTranslation({
    required String prompt,
    required String userAnswer,
    required String expectedAnswer,
    required TranslationQuizDirection direction,
    AiCancellationToken? cancellationToken,
  }) async {
    final trimmedAnswer = userAnswer.trim();
    if (trimmedAnswer.isEmpty) {
      throw const FormatException('Answer cannot be empty.');
    }

    final token = cancellationToken ?? AiCancellationToken();
    final provider = await _requireProvider();
    final sourceLanguage = await settings.getSourceLanguage();
    final translationLanguage = await settings.getTranslationLanguage();
    final promptLanguage =
        direction == TranslationQuizDirection.translationToSource
            ? translationLanguage
            : sourceLanguage;
    final answerLanguage =
        direction == TranslationQuizDirection.translationToSource
            ? sourceLanguage
            : translationLanguage;

    token.throwIfCancelled();
    final data = await _generateJson(
      provider: provider,
      maxOutputTokens: _checkOutputTokens(provider),
      cancellationToken: token,
      prompt: '''
Grade a learner's translation for a language quiz.

Context:
- Prompt language ($promptLanguage): ${jsonEncode(prompt)}
- Expected answer language ($answerLanguage): ${jsonEncode(expectedAnswer)}
- Learner answer ($answerLanguage): ${jsonEncode(trimmedAnswer)}

Grading rules:
- Accept correct meaning, including reasonable paraphrases and minor punctuation or capitalization differences.
- Be strict when meaning drifts, key vocabulary sense is wrong, or grammar changes the intended message.
- If incorrect, provide a short helpful feedback note, a corrected answer in $answerLanguage, and a learner-friendly pronunciation transcription of that corrected answer (latin characters for most languages; pinyin for Mandarin Chinese; romaji for Japanese when appropriate).
- If correct, feedback may briefly confirm what was good; correctedAnswer and transcription may be empty strings. Optionally still fill transcription for the accepted answer.

Return exactly: {"correct":true|false,"feedback":"...","correctedAnswer":"...","transcription":"..."}
''',
      validate: (data) {
        final correct = data['correct'];
        if (correct is! bool) {
          throw const FormatException('Missing correct boolean.');
        }
        _requiredString(data, 'feedback');
        final corrected = data['correctedAnswer'];
        if (corrected != null && corrected is! String) {
          throw const FormatException('correctedAnswer must be a string.');
        }
        final transcription = data['transcription'];
        if (transcription != null && transcription is! String) {
          throw const FormatException('transcription must be a string.');
        }
        if (correct == false) {
          final value = corrected is String ? corrected.trim() : '';
          if (value.isEmpty) {
            throw const FormatException(
              'correctedAnswer is required when incorrect.',
            );
          }
          final transcriptionValue =
              transcription is String ? transcription.trim() : '';
          if (transcriptionValue.isEmpty) {
            throw const FormatException(
              'transcription is required when incorrect.',
            );
          }
        }
      },
      responseSchema: AiResponseSchema.translationCheck,
      languageCodes: _languageCodes(promptLanguage, answerLanguage),
    );

    final isCorrect = data['correct'] as bool;
    final correctedRaw = data['correctedAnswer'];
    final corrected =
        correctedRaw is String && correctedRaw.trim().isNotEmpty
            ? correctedRaw.trim()
            : null;
    final transcriptionRaw = data['transcription'];
    final transcription =
        transcriptionRaw is String && transcriptionRaw.trim().isNotEmpty
            ? transcriptionRaw.trim()
            : null;

    return TranslationCheckResult(
      isCorrect: isCorrect,
      feedback: (data['feedback'] as String).trim(),
      correctedAnswer: isCorrect ? corrected : (corrected ?? expectedAnswer),
      transcription: transcription,
    );
  }

  Future<GeneratedText> _generateLocalText({
    required List<VocabularyEntry> availableVocabulary,
    required List<VocabularyEntry> annotationVocabulary,
    required List<String> categories,
    required int targetWordCount,
    required int outsideVocabularyPercent,
    required String sourceLanguage,
    required String translationLanguage,
    required AiCancellationToken cancellationToken,
    AiProgressCallback? onProgress,
  }) async {
    final client = await (_clientFactory ?? AiProviderClientFactory(settings))
        .create(AiProviderType.onDevice);
    final batchCount = max(
      1,
      (targetWordCount / onDevicePassageWordsPerBatch).ceil(),
    );
    final batches = partitionVocabularyForBatches(
      availableVocabulary,
      batchCount,
    );
    final wordTargets = distributeTarget(targetWordCount, batchCount);
    final sources = <String>[];
    final translations = <String>[];
    var title = '';
    var titleTranslation = '';
    var theme = '';

    for (var index = 0; index < batchCount; index++) {
      cancellationToken.throwIfCancelled();
      onProgress?.call(
        AiGenerationProgress(
          AiGenerationStage.generatingText,
          current: index + 1,
          total: batchCount,
        ),
      );
      final isFirst = index == 0;
      final schema =
          isFirst
              ? AiResponseSchema.passageStart
              : AiResponseSchema.passageSegment;
      final basePrompt = _localPassagePrompt(
        sourceLanguage: sourceLanguage,
        translationLanguage: translationLanguage,
        targetWords: wordTargets[index],
        outsideVocabularyPercent: outsideVocabularyPercent,
        isFirst: isFirst,
        theme: theme,
        previousSource: sources.isEmpty ? null : _continuityTail(sources.last),
        previousTranslation:
            translations.isEmpty ? null : _continuityTail(translations.last),
        vocabulary: const [],
      );
      final inputBudget = await _localInputBudget(
        client,
        outputReserve: onDeviceTextOutputTokens,
      );
      final vocabulary = await _fitVocabulary(
        client: client,
        candidates: batches[index],
        inputBudget: inputBudget,
        responseSchema: schema,
        buildPrompt:
            (entries) => _localPassagePrompt(
              sourceLanguage: sourceLanguage,
              translationLanguage: translationLanguage,
              targetWords: wordTargets[index],
              outsideVocabularyPercent: outsideVocabularyPercent,
              isFirst: isFirst,
              theme: theme,
              previousSource:
                  sources.isEmpty ? null : _continuityTail(sources.last),
              previousTranslation:
                  translations.isEmpty
                      ? null
                      : _continuityTail(translations.last),
              vocabulary: entries,
            ),
      );
      final prompt =
          vocabulary.isEmpty
              ? basePrompt
              : _localPassagePrompt(
                sourceLanguage: sourceLanguage,
                translationLanguage: translationLanguage,
                targetWords: wordTargets[index],
                outsideVocabularyPercent: outsideVocabularyPercent,
                isFirst: isFirst,
                theme: theme,
                previousSource:
                    sources.isEmpty ? null : _continuityTail(sources.last),
                previousTranslation:
                    translations.isEmpty
                        ? null
                        : _continuityTail(translations.last),
                vocabulary: vocabulary,
              );
      final data = await _generateJson(
        provider: AiProviderType.onDevice,
        prompt: prompt,
        maxOutputTokens: onDeviceTextOutputTokens,
        cancellationToken: cancellationToken,
        responseSchema: schema,
        languageCodes: _languageCodes(sourceLanguage, translationLanguage),
        client: client,
        validate: (data) {
          _requiredString(data, 'source');
          _requiredString(data, 'translation');
          if (isFirst) {
            _requiredString(data, 'title');
            _requiredString(data, 'titleTranslation');
            _requiredString(data, 'theme');
          }
        },
      );
      if (isFirst) {
        title = (data['title'] as String).trim();
        titleTranslation = (data['titleTranslation'] as String).trim();
        theme = (data['theme'] as String).trim();
      }
      sources.add((data['source'] as String).trim());
      translations.add((data['translation'] as String).trim());
    }

    cancellationToken.throwIfCancelled();
    final source = sources.join('\n\n');
    final translation = translations.join('\n\n');
    onProgress?.call(
      const AiGenerationProgress(AiGenerationStage.annotatingSource),
    );
    final annotations = annotateWithVocabulary(source, annotationVocabulary);
    cancellationToken.throwIfCancelled();
    onProgress?.call(const AiGenerationProgress(AiGenerationStage.saving));
    return GeneratedText(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      titleTranslation: titleTranslation,
      source: source,
      translation: translation,
      createdAt: DateTime.now(),
      categories: List.unmodifiable(categories),
      targetWordCount: targetWordCount,
      outsideVocabularyPercent: outsideVocabularyPercent,
      provider: AiProviderType.onDevice,
      sourceAnnotations: List.unmodifiable(annotations),
      translationAnnotations: const [],
    );
  }

  Future<TranslationQuiz> _generateLocalQuiz({
    required List<VocabularyEntry> availableVocabulary,
    required List<String> categories,
    required int sentenceCount,
    required TranslationQuizDirection direction,
    required String sourceLanguage,
    required String translationLanguage,
    required AiCancellationToken cancellationToken,
    AiProgressCallback? onProgress,
  }) async {
    final client = await (_clientFactory ?? AiProviderClientFactory(settings))
        .create(AiProviderType.onDevice);
    final batchCount = sentenceCount ~/ onDeviceQuizItemsPerBatch;
    final batches = partitionVocabularyForBatches(
      availableVocabulary,
      batchCount,
    );
    final pairs = <Map<String, dynamic>>[];
    final seenSources = <String>{};

    for (var index = 0; index < batchCount; index++) {
      cancellationToken.throwIfCancelled();
      onProgress?.call(
        AiGenerationProgress(
          AiGenerationStage.generatingQuiz,
          current: index + 1,
          total: batchCount,
        ),
      );
      final inputBudget = await _localInputBudget(
        client,
        outputReserve: onDeviceQuizOutputTokens,
      );
      String buildPrompt(List<VocabularyEntry> entries) => _localQuizPrompt(
        sourceLanguage: sourceLanguage,
        translationLanguage: translationLanguage,
        vocabulary: entries,
        previousSources: seenSources,
      );
      final vocabulary = await _fitVocabulary(
        client: client,
        candidates: batches[index],
        inputBudget: inputBudget,
        responseSchema: AiResponseSchema.quizBatch,
        buildPrompt: buildPrompt,
      );
      final data = await _generateJson(
        provider: AiProviderType.onDevice,
        prompt: buildPrompt(vocabulary),
        maxOutputTokens: onDeviceQuizOutputTokens,
        cancellationToken: cancellationToken,
        responseSchema: AiResponseSchema.quizBatch,
        languageCodes: _languageCodes(sourceLanguage, translationLanguage),
        client: client,
        validate: (data) {
          final sentences = data['sentences'];
          if (sentences is! List ||
              sentences.length != onDeviceQuizItemsPerBatch) {
            throw const FormatException('Expected exactly 5 sentences.');
          }
          final batchSeen = <String>{};
          for (final item in sentences) {
            if (item is! Map) {
              throw const FormatException('Each sentence must be an object.');
            }
            final map = Map<String, dynamic>.from(item);
            final source = _requiredString(map, 'source').trim().toLowerCase();
            _requiredString(map, 'translation');
            if (seenSources.contains(source) || !batchSeen.add(source)) {
              throw const FormatException('Quiz sentences must be unique.');
            }
          }
        },
      );
      for (final item in data['sentences'] as List<dynamic>) {
        final pair = Map<String, dynamic>.from(item as Map);
        seenSources.add((pair['source'] as String).trim().toLowerCase());
        pairs.add(pair);
      }
    }

    cancellationToken.throwIfCancelled();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return TranslationQuiz(
      items: List.unmodifiable([
        for (var index = 0; index < pairs.length; index++)
          TranslationQuizItem.fromBilingualPair(
            id: '${stamp}_$index',
            source: pairs[index]['source'] as String,
            translation: pairs[index]['translation'] as String,
            direction: direction,
          ),
      ]),
      categories: List.unmodifiable(categories),
      sentenceCount: sentenceCount,
      direction: direction,
      provider: AiProviderType.onDevice,
    );
  }

  Future<int> _localInputBudget(
    AiProviderClient client, {
    required int outputReserve,
  }) async {
    var limit = 4096;
    if (client is OnDeviceAiProviderClient) {
      final availability = await client.getAvailability();
      limit = availability.totalTokenLimit;
    }
    return min(
      onDeviceMaxInputTokens,
      max(256, limit - outputReserve - onDeviceSafetyTokens),
    );
  }

  Future<List<VocabularyEntry>> _fitVocabulary({
    required AiProviderClient client,
    required List<VocabularyEntry> candidates,
    required int inputBudget,
    required AiResponseSchema responseSchema,
    required String Function(List<VocabularyEntry>) buildPrompt,
  }) async {
    final selected = <VocabularyEntry>[];
    for (final entry in candidates) {
      final trial = [...selected, entry];
      final prompt = buildPrompt(trial);
      final count = await _countLocalInput(client, prompt, responseSchema);
      if (count > inputBudget) continue;
      selected.add(entry);
    }
    return selected;
  }

  Future<int> _countLocalInput(
    AiProviderClient client,
    String prompt,
    AiResponseSchema schema,
  ) async {
    if (client is OnDeviceAiProviderClient) {
      try {
        final availability = await client.getAvailability();
        if (availability.supportsTokenCounting) {
          return await client.countTokens(
            prompt,
            systemInstruction: OnDeviceAiProviderClient.jsonSystemInstruction,
            responseSchema: schema,
          );
        }
      } catch (_) {
        // Fall back to the deliberately conservative local estimate.
      }
    }
    return estimateLocalTokens(prompt);
  }

  static String _localPassagePrompt({
    required String sourceLanguage,
    required String translationLanguage,
    required int targetWords,
    required int outsideVocabularyPercent,
    required bool isFirst,
    required String theme,
    required String? previousSource,
    required String? previousTranslation,
    required List<VocabularyEntry> vocabulary,
  }) {
    final continuity =
        isFirst
            ? 'Invent a concise bilingual title and a short theme for the whole passage.'
            : '''Continue the same passage and theme: ${jsonEncode(theme)}.
The prior segment ended with:
- $sourceLanguage: ${jsonEncode(previousSource)}
- $translationLanguage: ${jsonEncode(previousTranslation)}
Do not repeat those sentences.''';
    return '''
Write one coherent bilingual passage segment for language learning.

$continuity

Requirements:
- Source language: $sourceLanguage.
- Translation language: $translationLanguage.
- Write approximately $targetWords lexical words in the source segment.
- The translation must faithfully express the same segment.
- Aim for approximately $outsideVocabularyPercent% content vocabulary outside the supplied vocabulary.
- Weave supplied words and phrases in naturally. For sentence-like entries, reuse the pattern but never copy the sentence.
- Keep the output concise and self-contained.
- Return exactly ${isFirst ? '{"title":"...","titleTranslation":"...","theme":"...","source":"...","translation":"..."}' : '{"source":"...","translation":"..."}'}.

Vocabulary:
${jsonEncode(_vocabularyDump(vocabulary))}
''';
  }

  static String _localQuizPrompt({
    required String sourceLanguage,
    required String translationLanguage,
    required List<VocabularyEntry> vocabulary,
    required Set<String> previousSources,
  }) => '''
Create exactly 5 unique bilingual sentence pairs for a language-learning translation quiz.

Requirements:
- Source language: $sourceLanguage.
- Translation language: $translationLanguage.
- Each pair must express the same meaning and be natural and pedagogically useful.
- Vary topics and grammar. Do not repeat earlier source sentences.
- Weave supplied words and phrases in naturally. For sentence-like entries, reuse the pattern but never copy the sentence.
- Return exactly: {"sentences":[{"source":"...","translation":"..."}, ...]}.

Earlier source sentences to avoid:
${jsonEncode(previousSources.toList())}

Vocabulary:
${jsonEncode(_vocabularyDump(vocabulary))}
''';

  static List<Map<String, String>> _vocabularyDump(
    List<VocabularyEntry> vocabulary,
  ) => [
    for (final entry in vocabulary)
      {
        'source': entry.word,
        'translation': entry.translation,
        'category': entry.category,
      },
  ];

  static String _continuityTail(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 300) return trimmed;
    return trimmed.substring(trimmed.length - 300);
  }

  @visibleForTesting
  static int estimateLocalTokens(String text) {
    if (text.isEmpty) return 0;
    var cjkCharacters = 0;
    var otherCharacters = 0;
    for (final rune in text.runes) {
      if ((rune >= 0x3040 && rune <= 0x30ff) ||
          (rune >= 0x3400 && rune <= 0x9fff) ||
          (rune >= 0xac00 && rune <= 0xd7af)) {
        cjkCharacters++;
      } else {
        otherCharacters++;
      }
    }
    final estimate = cjkCharacters + (otherCharacters / 3).ceil();
    return (estimate * 1.2).ceil();
  }

  @visibleForTesting
  static List<int> distributeTarget(int total, int batchCount) {
    final base = total ~/ batchCount;
    final remainder = total % batchCount;
    return [
      for (var index = 0; index < batchCount; index++)
        base + (index < remainder ? 1 : 0),
    ];
  }

  @visibleForTesting
  static List<List<VocabularyEntry>> partitionVocabularyForBatches(
    List<VocabularyEntry> vocabulary,
    int batchCount,
  ) {
    if (batchCount <= 0) throw ArgumentError.value(batchCount, 'batchCount');
    final byCategory = <String, List<VocabularyEntry>>{};
    for (final entry in vocabulary) {
      byCategory.putIfAbsent(entry.category, () => []).add(entry);
    }
    final interleaved = <VocabularyEntry>[];
    var added = true;
    for (var offset = 0; added; offset++) {
      added = false;
      for (final entries in byCategory.values) {
        if (offset < entries.length) {
          interleaved.add(entries[offset]);
          added = true;
        }
      }
    }
    final batches = List.generate(batchCount, (_) => <VocabularyEntry>[]);
    for (var index = 0; index < interleaved.length; index++) {
      batches[index % batchCount].add(interleaved[index]);
    }
    return batches;
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
    AiResponseSchema? responseSchema,
    List<String> languageCodes = const [],
    AiProviderClient? client,
    AiCancellationToken? cancellationToken,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        final requestClient =
            client ??
            await (_clientFactory ?? AiProviderClientFactory(settings)).create(
              provider,
            );
        if (requestClient is OnDeviceAiProviderClient &&
            languageCodes.isNotEmpty &&
            !await requestClient.supportsLanguages(languageCodes)) {
          throw const AiProviderException(
            'The selected language is not supported by the on-device model.',
          );
        }
        final raw = await requestClient.generate(
          attempt == 0
              ? prompt
              : '$prompt\nThe previous response was invalid or incomplete. Return only complete valid JSON.',
          maxOutputTokens: maxOutputTokens,
          cancellationToken: cancellationToken,
          responseSchema: responseSchema,
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

  static List<String> _languageCodes(String first, String second) => [
    first,
    second,
  ].map(_languageCode).whereType<String>().toSet().toList(growable: false);

  static String? _languageCode(String language) => switch (language) {
    'English' => 'en',
    'French' => 'fr',
    'Spanish' => 'es',
    'German' => 'de',
    'Italian' => 'it',
    'Portuguese' => 'pt',
    'Chinese' => 'zh',
    'Japanese' => 'ja',
    'Korean' => 'ko',
    'Russian' => 'ru',
    'Arabic' => 'ar',
    _ => null,
  };

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
