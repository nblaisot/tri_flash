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

String _analysis(List<VocabularyEntry> entries) => jsonEncode({
  'entries': [
    for (final entry in entries)
      {
        'id': '${entry.id}',
        'kind': entry.word.endsWith('.') ? 'structure' : 'lexical',
        'lexicalTargets': entry.word.endsWith('.') ? <String>[] : [entry.word],
        'grammarStructures':
            entry.word.endsWith('.') ? ['subject + verb'] : <String>[],
      },
  ],
});

String _annotations(List<Map<String, Object>> words) =>
    jsonEncode({'words': words});

Map<String, Object> _word(String surface, String translation) => {
  'surface': surface,
  'pronunciation': 'pron-$surface',
  'contextualTranslation': translation,
};

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
      jsonEncode({'source': 'Je vois un chat.', 'translation': 'I see a cat.'}),
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
    expect(result.translation, 'I see a cat.');
    expect(client.tokenLimits, [AiGenerationService.analysisOutputTokens]);
  });

  test('retries once when the provider returns malformed JSON', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      'not json',
      '{"source":"bonjour","translation":"hello"}',
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
    expect(client.calls, 2);
  });

  test('analyzes the full corpus and produces complete annotations', () async {
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
      _analysis(entries),
      jsonEncode({'source': 'Salut ami', 'translation': 'Hello friend'}),
      _annotations([_word('Salut', 'Hello'), _word('ami', 'friend')]),
      _annotations([_word('Hello', 'Salut'), _word('friend', 'ami')]),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );
    final progress = <AiGenerationProgress>[];

    final generated = await service.generateText(
      availableVocabulary: entries,
      categories: const ['test'],
      targetWordCount: 20,
      outsideVocabularyPercent: 5,
      onProgress: progress.add,
    );

    expect(generated.sourceAnnotations.map((item) => item.surface), [
      'Salut',
      'ami',
    ]);
    expect(generated.translationAnnotations, hasLength(2));
    expect(generated.sourceAnnotations.last.start, 6);
    expect(client.prompts.first, contains('"id":"1"'));
    expect(client.prompts.first, contains('"id":"2"'));
    expect(client.prompts[1], contains('Forbidden verbatim sentences'));
    expect(client.prompts[1], contains('Je vais au marché.'));
    expect(client.tokenLimits, [4000, 8000, 4000, 4000]);
    expect(progress.last.stage, AiGenerationStage.saving);
  });

  test('rejects annotations that leave lexical text unannotated', () async {
    final settings = AiSettingsService();
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'bonjour',
      transcription: '',
      translation: 'hello',
    );
    final invalid = _annotations([]);
    final client = _FakeClient([
      _analysis([entry]),
      jsonEncode({'source': 'Salut', 'translation': 'Hello'}),
      invalid,
      invalid,
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    await expectLater(
      service.generateText(
        availableVocabulary: const [entry],
        categories: const ['test'],
        targetWordCount: 20,
        outsideVocabularyPercent: 5,
      ),
      throwsA(isA<AiAnnotationException>()),
    );
  });

  test('accepts complete accented, Arabic, and CJK annotations', () async {
    final settings = AiSettingsService();
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'été',
      transcription: '',
      translation: 'summer',
    );
    final client = _FakeClient([
      _analysis([entry]),
      jsonEncode({
        'source': 'été مرحبا 世界',
        'translation': 'summer hello world',
      }),
      _annotations([
        _word('été', 'summer'),
        _word('مرحبا', 'hello'),
        _word('世界', 'world'),
      ]),
      _annotations([
        _word('summer', 'été'),
        _word('hello', 'مرحبا'),
        _word('world', '世界'),
      ]),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    final result = await service.generateText(
      availableVocabulary: const [entry],
      categories: const ['test'],
      targetWordCount: 20,
      outsideVocabularyPercent: 5,
    );

    expect(result.sourceAnnotations.map((item) => item.surface), [
      'été',
      'مرحبا',
      '世界',
    ]);
    expect(result.sourceAnnotations.last.end, result.source.length);
  });

  test('aligns words while preserving punctuation and whitespace locally', () {
    const text = ' \nBonjour, l’été — مرحبا، שָׁלוֹם! 世界。Bonjour ';
    final words = [
      _word('Bonjour', 'Hello'),
      _word('l’été', 'the summer'),
      _word('مرحبا', 'hello'),
      _word('שָׁלוֹם', 'peace'),
      _word('世界', 'world'),
      _word('Bonjour', 'Hello'),
    ];

    final annotations = AiGenerationService.alignAnnotationWords(text, words);

    expect(annotations.map((item) => item.surface), [
      'Bonjour',
      'l’été',
      'مرحبا',
      'שָׁלוֹם',
      '世界',
      'Bonjour',
    ]);
    for (final annotation in annotations) {
      expect(
        text.substring(annotation.start, annotation.end),
        annotation.surface,
      );
    }
    expect(annotations.first.start, 2);
    expect(annotations.last.start, text.lastIndexOf('Bonjour'));
  });

  test('applies global offsets without including separators', () {
    const text = 'Hello, world!';
    final annotations = AiGenerationService.alignAnnotationWords(text, [
      _word('Hello', 'Bonjour'),
      _word('world', 'monde'),
    ], globalOffset: 120);

    expect(annotations.first.start, 120);
    expect(annotations.first.end, 125);
    expect(annotations.last.start, 127);
    expect(annotations.last.end, 132);
  });

  test('rejects omitted, altered, reordered, duplicate, and invalid words', () {
    final invalidWordLists = <List<Map<String, Object>>>[
      [_word('one', 'un'), _word('three', 'trois')],
      [_word('One', 'un'), _word('two', 'deux'), _word('three', 'trois')],
      [_word('two', 'deux'), _word('one', 'un'), _word('three', 'trois')],
      [
        _word('one', 'un'),
        _word('two', 'deux'),
        _word('three', 'trois'),
        _word('three', 'trois'),
      ],
      [_word('one,', 'un'), _word('two', 'deux'), _word('three', 'trois')],
      [
        {'surface': 'one', 'pronunciation': '', 'contextualTranslation': 'un'},
        _word('two', 'deux'),
        _word('three', 'trois'),
      ],
      [
        {
          'surface': ',',
          'pronunciation': 'comma',
          'contextualTranslation': 'virgule',
        },
      ],
    ];

    for (final words in invalidWordLists) {
      expect(
        () => AiGenerationService.alignAnnotationWords('one two three', words),
        throwsA(isA<Exception>()),
      );
    }
  });

  test('targeted retry recovers an omitted word annotation', () async {
    final settings = AiSettingsService();
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'bonjour',
      transcription: '',
      translation: 'hello',
    );
    final client = _FakeClient([
      _analysis([entry]),
      jsonEncode({'source': 'Salut ami', 'translation': 'Hello friend'}),
      _annotations([_word('Salut', 'Hello')]),
      _annotations([_word('Salut', 'Hello'), _word('ami', 'friend')]),
      _annotations([_word('Hello', 'Salut'), _word('friend', 'ami')]),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    final result = await service.generateText(
      availableVocabulary: const [entry],
      categories: const ['test'],
      targetWordCount: 20,
      outsideVocabularyPercent: 5,
    );

    expect(result.sourceAnnotations, hasLength(2));
    expect(client.calls, 5);
    expect(client.prompts[3], contains('at the end were omitted'));
  });

  test('annotation failure identifies the language stage and chunk', () async {
    final settings = AiSettingsService();
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'bonjour',
      transcription: '',
      translation: 'hello',
    );
    final client = _FakeClient([
      _analysis([entry]),
      jsonEncode({'source': 'Salut', 'translation': 'Hello'}),
      _annotations([]),
      _annotations([]),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    try {
      await service.generateText(
        availableVocabulary: const [entry],
        categories: const ['test'],
        targetWordCount: 20,
        outsideVocabularyPercent: 5,
      );
      fail('Expected annotation generation to fail.');
    } on AiAnnotationException catch (error) {
      expect(error.stage, AiGenerationStage.annotatingSource);
      expect(error.chunk, 1);
      expect(error.totalChunks, 1);
    }
  });

  test('maintains exact global offsets across multiple chunks', () async {
    final settings = AiSettingsService();
    const entry = VocabularyEntry(
      id: 1,
      category: 'test',
      word: 'mot',
      transcription: '',
      translation: 'word',
    );
    final source = List.generate(90, (index) => 'mot$index').join(' ');
    final translation = List.generate(90, (index) => 'word$index').join(' ');
    final responses = <Object>[
      _analysis([entry]),
      jsonEncode({'source': source, 'translation': translation}),
    ];
    for (final text in [source, translation]) {
      for (final chunk in AiGenerationService.chunkText(text)) {
        responses.add(
          _annotations([
            for (final match in RegExp(r'[A-Za-z0-9]+').allMatches(chunk))
              _word(match.group(0)!, 'translation'),
          ]),
        );
      }
    }
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, _FakeClient(responses)),
    );

    final result = await service.generateText(
      availableVocabulary: const [entry],
      categories: const ['test'],
      targetWordCount: 500,
      outsideVocabularyPercent: 5,
    );

    expect(result.sourceAnnotations, hasLength(90));
    expect(result.translationAnnotations, hasLength(90));
    expect(result.sourceAnnotations.last.end, source.length);
    expect(result.translationAnnotations.last.end, translation.length);
    expect(
      result.source.substring(
        result.sourceAnnotations[80].start,
        result.sourceAnnotations[80].end,
      ),
      'mot80',
    );
  });

  test('batches every corpus entry without random omission', () {
    final entries = List.generate(
      401,
      (index) => VocabularyEntry(
        id: index,
        category: 'test',
        word: 'word$index',
        transcription: '',
        translation: 'translation$index',
      ),
    );
    final batches = AiGenerationService.batchCorpus(entries);

    expect(batches.map((batch) => batch.length), [200, 200, 1]);
    expect(
      batches.expand((batch) => batch).map((entry) => entry.id).toSet(),
      hasLength(401),
    );
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
        categories: const ['test'],
        targetWordCount: 20,
        outsideVocabularyPercent: 5,
        cancellationToken: token,
      ),
      throwsA(isA<AiGenerationCancelled>()),
    );
  });
}
