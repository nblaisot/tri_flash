import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_generation_service.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';

class _FakeClient implements AiProviderClient {
  _FakeClient(this.responses);

  final List<Object> responses;
  final prompts = <String>[];
  final tokenLimits = <int>[];
  var calls = 0;

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    prompts.add(prompt);
    tokenLimits.add(maxOutputTokens);
    final response = responses[calls++];
    if (response is Exception) throw response;
    return response as String;
  }
}

class _FakeFactory extends AiProviderClientFactory {
  _FakeFactory(super.settings, this.client);

  final AiProviderClient client;

  @override
  Future<AiProviderClient> create(AiProviderType provider) async => client;
}

const _salut = VocabularyEntry(
  id: 10,
  category: 'test',
  word: 'Salut',
  transcription: 'sa.ly',
  translation: 'hello',
);

const _ami = VocabularyEntry(
  id: 11,
  category: 'test',
  word: 'ami',
  transcription: 'a.mi',
  translation: 'friend',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'openai',
      'ai_source_language': 'French',
      'ai_translation_language': 'English',
    });
  });

  test('parses a bilingual sentence JSON response', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      jsonEncode({
        'source': 'Je vois un chat.',
        'transcription': 'ʒə vwa œ̃ ʃa',
        'translation': 'I see a cat.',
      }),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    final result = await service.generateSentence(
      const VocabularyEntry(
        id: 1,
        category: 'animals',
        word: 'chat',
        transcription: 'ʃa',
        translation: 'cat',
      ),
    );

    expect(result.source, 'Je vois un chat.');
    expect(result.transcription, 'ʒə vwa œ̃ ʃa');
    expect(result.translation, 'I see a cat.');
    expect(client.tokenLimits, [AiGenerationService.sentenceOutputTokens]);
  });

  test('retries once when the provider returns malformed JSON', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      'not json',
      '{"source":"bonjour","transcription":"bɔ̃.ʒuʁ","translation":"hello"}',
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    final result = await service.generateSentence(
      const VocabularyEntry(
        id: 1,
        category: 'default',
        word: 'bonjour',
        transcription: 'bɔ̃.ʒuʁ',
        translation: 'hello',
      ),
    );

    expect(result.translation, 'hello');
    expect(result.transcription, 'bɔ̃.ʒuʁ');
    expect(client.calls, 2);
  });

  test('generates bilingual text in one LLM call then annotates locally', () async {
    final settings = AiSettingsService();
    const entries = [
      VocabularyEntry(
        id: 1,
        category: 'test',
        word: 'bonjour',
        transcription: '',
        translation: 'hello',
      ),
      VocabularyEntry(
        id: 2,
        category: 'test',
        word: 'Je vais au marché.',
        transcription: '',
        translation: 'I am going to the market.',
      ),
    ];
    final client = _FakeClient([
      jsonEncode({
        'title': 'Salut à un ami',
        'titleTranslation': 'Hello to a friend',
        'source': 'Salut ami',
        'translation': 'Hello friend',
      }),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );
    final progress = <AiGenerationProgress>[];

    final generated = await service.generateText(
      availableVocabulary: entries,
      annotationVocabulary: const [_salut, _ami],
      categories: const ['test'],
      targetWordCount: 20,
      outsideVocabularyPercent: 5,
      onProgress: progress.add,
    );

    expect(generated.sourceAnnotations.map((item) => item.surface), [
      'Salut',
      'ami',
    ]);
    expect(generated.title, 'Salut à un ami');
    expect(generated.titleTranslation, 'Hello to a friend');
    expect(generated.sourceAnnotations.first.pronunciation, 'sa.ly');
    expect(generated.sourceAnnotations.last.contextualTranslation, 'friend');
    expect(generated.translationAnnotations, isEmpty);
    expect(generated.sourceAnnotations.last.start, 6);
    expect(client.calls, 1);
    expect(client.tokenLimits, [8000]);
    expect(client.prompts.single, contains('"source":"bonjour"'));
    expect(client.prompts.single, contains('Je vais au marché.'));
    expect(
      client.prompts.single,
      contains('Distinguish short reusable items'),
    );
    expect(
      client.prompts.single,
      contains('Never copy any sentence-like source'),
    );
    expect(progress.map((item) => item.stage).toList(), [
      AiGenerationStage.generatingText,
      AiGenerationStage.annotatingSource,
      AiGenerationStage.saving,
    ]);
  });

  test('fails fast when the corpus has too many entries', () async {
    final settings = AiSettingsService();
    final entries = List.generate(
      AiGenerationService.maxCorpusEntries + 1,
      (index) => VocabularyEntry(
        id: index,
        category: 'test',
        word: 'w$index',
        transcription: '',
        translation: 't$index',
      ),
    );
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, _FakeClient([])),
    );

    await expectLater(
      service.generateText(
        availableVocabulary: entries,
        annotationVocabulary: entries,
        categories: const ['test'],
        targetWordCount: 20,
        outsideVocabularyPercent: 5,
      ),
      throwsA(isA<AiCorpusTooLargeException>()),
    );
  });

  test('fails fast when the serialized corpus exceeds the character limit', () {
    expect(
      AiGenerationService.isCorpusTooLarge(
        entryCount: 10,
        corpusJsonCharacters: AiGenerationService.maxCorpusCharacters + 1,
      ),
      isTrue,
    );
    expect(
      AiGenerationService.isCorpusTooLarge(
        entryCount: 10,
        corpusJsonCharacters: AiGenerationService.maxCorpusCharacters,
      ),
      isFalse,
    );
  });

  test('maps provider context-length errors to corpus too large', () async {
    final settings = AiSettingsService();
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'bonjour',
      transcription: '',
      translation: 'hello',
    );
    final client = _FakeClient([
      const AiProviderException(
        'OpenAI request failed (400): context_length_exceeded',
      ),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    await expectLater(
      service.generateText(
        availableVocabulary: const [entry],
        annotationVocabulary: const [entry],
        categories: const ['test'],
        targetWordCount: 20,
        outsideVocabularyPercent: 5,
      ),
      throwsA(isA<AiCorpusTooLargeException>()),
    );
  });

  test('detects common corpus size error messages', () {
    expect(
      AiGenerationService.isCorpusSizeProviderError(
        'maximum context length exceeded',
      ),
      isTrue,
    );
    expect(
      AiGenerationService.isCorpusSizeProviderError('HTTP 413 Payload Too Large'),
      isTrue,
    );
    expect(
      AiGenerationService.isCorpusSizeProviderError('rate limit exceeded'),
      isFalse,
    );
  });

  test('prefers longer compound matches over shorter prefixes', () {
    const vocabulary = [
      VocabularyEntry(
        id: 1,
        category: 'test',
        word: '中',
        transcription: 'zhōng',
        translation: 'middle',
      ),
      VocabularyEntry(
        id: 2,
        category: 'test',
        word: '中国',
        transcription: 'Zhōngguó',
        translation: 'China',
      ),
    ];

    final annotations = AiGenerationService.annotateWithVocabulary(
      '我在中国。',
      vocabulary,
    );

    expect(annotations.map((item) => item.surface), ['中国']);
    expect(annotations.single.pronunciation, 'Zhōngguó');
  });

  test('leaves unknown words unannotated and skips punctuation', () {
    const vocabulary = [
      VocabularyEntry(
        id: 1,
        category: 'test',
        word: 'été',
        transcription: 'e.te',
        translation: 'summer',
      ),
    ];

    final annotations = AiGenerationService.annotateWithVocabulary(
      'été مرحبا 世界',
      vocabulary,
    );

    expect(annotations, hasLength(1));
    expect(annotations.single.surface, 'été');
    expect(annotations.single.end, 3);
  });

  test('prefers active entries when duplicate surfaces exist', () {
    const vocabulary = [
      VocabularyEntry(
        id: 1,
        category: 'a',
        word: '朋友',
        transcription: 'inactive',
        translation: 'inactive meaning',
        isActive: false,
      ),
      VocabularyEntry(
        id: 2,
        category: 'b',
        word: '朋友',
        transcription: 'péngyou',
        translation: 'friend',
        isActive: true,
      ),
    ];

    final index = AiGenerationService.buildVocabularyIndex(vocabulary);
    expect(index['朋友']!.transcription, 'péngyou');

    final annotations = AiGenerationService.annotateWithVocabulary(
      '我的朋友',
      vocabulary,
    );
    expect(annotations.single.pronunciation, 'péngyou');
  });

  test('copies transcription and translation from vocabulary entries', () {
    const vocabulary = [
      VocabularyEntry(
        id: 1,
        category: 'test',
        word: '你好',
        transcription: 'nǐ hǎo',
        translation: 'hello',
      ),
    ];

    final annotations = AiGenerationService.annotateWithVocabulary(
      '你好',
      vocabulary,
    );

    expect(annotations.single.pronunciation, 'nǐ hǎo');
    expect(annotations.single.contextualTranslation, 'hello');
  });

  test('annotates long source text in one local pass', () async {
    final settings = AiSettingsService();
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'mot',
      transcription: 'mo',
      translation: 'word',
    );
    final source = List.generate(90, (index) => 'mot$index').join(' ');
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(
        settings,
        _FakeClient([
          jsonEncode({
            'title': 'Lots of words',
            'titleTranslation': 'Beaucoup de mots',
            'source': source,
            'translation': 'translation',
          }),
        ]),
      ),
    );
    final annotationVocabulary = List.generate(
      90,
      (index) => VocabularyEntry(
        id: index + 2,
        category: 'test',
        word: 'mot$index',
        transcription: 'mo$index',
        translation: 'word$index',
      ),
    );

    final result = await service.generateText(
      availableVocabulary: const [entry],
      annotationVocabulary: annotationVocabulary,
      categories: const ['test'],
      targetWordCount: 500,
      outsideVocabularyPercent: 5,
    );

    expect(result.sourceAnnotations, hasLength(90));
    expect(result.translationAnnotations, isEmpty);
    expect(result.sourceAnnotations.last.end, source.length);
    expect(
      result.source.substring(
        result.sourceAnnotations[80].start,
        result.sourceAnnotations[80].end,
      ),
      'mot80',
    );
    expect(result.sourceAnnotations, hasLength(90));
  });

  test('chunks text within character and estimated lexical limits', () {
    final chunks = AiGenerationService.chunkText(
      List.filled(200, 'mot').join(' '),
    );
    expect(chunks.join(), List.filled(200, 'mot').join(' '));
    expect(chunks.every((chunk) => chunk.length <= 600), isTrue);
    expect(
      chunks.every(
        (chunk) => AiGenerationService.estimateWordCount(chunk) <= 80,
      ),
      isTrue,
    );
    expect(AiGenerationService.estimateWordCount('欢迎朋友 hello-world مرحبا'), 6);
  });

  test('validates target word-count boundaries', () async {
    final settings = AiSettingsService();
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, _FakeClient([])),
    );
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'word',
      transcription: '',
      translation: 'mot',
    );
    for (final invalid in [19, 501]) {
      await expectLater(
        service.generateText(
          availableVocabulary: const [entry],
          annotationVocabulary: const [entry],
          categories: const ['test'],
          targetWordCount: invalid,
          outsideVocabularyPercent: 5,
        ),
        throwsFormatException,
      );
    }
  });

  test('honors cancellation before a provider request', () async {
    final settings = AiSettingsService();
    final token = AiCancellationToken()..cancel();
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, _FakeClient([])),
    );

    await expectLater(
      service.generateText(
        availableVocabulary: const [
          VocabularyEntry(
            id: 1,
            category: 'test',
            word: 'word',
            transcription: '',
            translation: 'mot',
          ),
        ],
        annotationVocabulary: const [
          VocabularyEntry(
            id: 1,
            category: 'test',
            word: 'word',
            transcription: '',
            translation: 'mot',
          ),
        ],
        categories: const ['test'],
        targetWordCount: 20,
        outsideVocabularyPercent: 5,
        cancellationToken: token,
      ),
      throwsA(isA<AiGenerationCancelled>()),
    );
  });
}
