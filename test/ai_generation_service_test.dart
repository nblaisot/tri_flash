import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_generation_service.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';

class _FakeClient implements AiProviderClient {
  _FakeClient(this.responses);
  final List<String> responses;
  var calls = 0;

  @override
  Future<String> generate(String prompt) async => responses[calls++];
}

class _FakeFactory extends AiProviderClientFactory {
  _FakeFactory(super.settings, this.client);
  final AiProviderClient client;

  @override
  Future<AiProviderClient> create(AiProviderType provider) async => client;
}

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

  test('samples vocabulary within the known-word budget', () {
    final entries = List.generate(
      20,
      (index) => VocabularyEntry(
        id: index,
        category: 'test',
        word: 'word$index',
        transcription: '',
        translation: 'translation$index',
      ),
    );

    final selected = AiGenerationService.selectVocabulary(
      entries,
      targetWordCount: 20,
      outsideVocabularyPercent: 5,
      random: Random(1),
    );

    expect(selected, hasLength(19));
  });

  test('counts CJK characters and Latin words', () {
    expect(AiGenerationService.estimateWordCount('欢迎朋友 hello-world'), 5);
  });

  test('snapshots matches from the full category vocabulary', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      '{"source":"alpha gamma","translation":"un trois"}',
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );
    const entries = [
      VocabularyEntry(
        id: 1,
        category: 'test',
        word: 'alpha',
        transcription: 'a',
        translation: 'un',
      ),
      VocabularyEntry(
        id: 2,
        category: 'test',
        word: 'beta',
        transcription: 'b',
        translation: 'deux',
      ),
      VocabularyEntry(
        id: 3,
        category: 'test',
        word: 'gamma',
        transcription: 'g',
        translation: 'trois',
      ),
    ];

    final generated = await service.generateText(
      availableVocabulary: entries,
      categories: const ['test'],
      targetWordCount: 1,
      outsideVocabularyPercent: 5,
    );

    expect(generated.vocabulary.map((entry) => entry.id), containsAll([1, 3]));
    expect(generated.vocabulary.map((entry) => entry.id), isNot(contains(2)));
  });
}
