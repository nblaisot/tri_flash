import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/translation_quiz_sheet.dart';
import 'package:tri_flash/services/ai/ai_generation_service.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';

class _FakeClient implements AiProviderClient {
  _FakeClient(this.responses);

  final List<Object> responses;
  final prompts = <String>[];
  var calls = 0;

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
    AiResponseSchema? responseSchema,
  }) async {
    cancellationToken?.throwIfCancelled();
    prompts.add(prompt);
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'openai',
      'ai_source_language': 'French',
      'ai_translation_language': 'English',
    });
  });

  test('maps quiz items from translation to source by default', () {
    final item = TranslationQuizItem.fromBilingualPair(
      id: '1',
      source: 'Bonjour ami',
      translation: 'Hello friend',
      direction: TranslationQuizDirection.translationToSource,
    );
    expect(item.prompt, 'Hello friend');
    expect(item.expectedAnswer, 'Bonjour ami');
  });

  test('maps quiz items from source to translation when flipped', () {
    final item = TranslationQuizItem.fromBilingualPair(
      id: '1',
      source: 'Bonjour ami',
      translation: 'Hello friend',
      direction: TranslationQuizDirection.sourceToTranslation,
    );
    expect(item.prompt, 'Bonjour ami');
    expect(item.expectedAnswer, 'Hello friend');
  });

  test('generates a translation quiz and maps direction', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      jsonEncode({
        'sentences': [
          {'source': 'Je vois un chat.', 'translation': 'I see a cat.'},
          {'source': 'Tu as un ami.', 'translation': 'You have a friend.'},
          {'source': 'Nous mangeons.', 'translation': 'We eat.'},
          {'source': 'Il lit un livre.', 'translation': 'He reads a book.'},
          {'source': 'Elle boit de l’eau.', 'translation': 'She drinks water.'},
        ],
      }),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    final quiz = await service.generateTranslationQuiz(
      availableVocabulary: const [
        VocabularyEntry(
          id: 1,
          category: 'test',
          word: 'chat',
          transcription: '',
          translation: 'cat',
        ),
      ],
      categories: const ['test'],
      sentenceCount: 5,
      direction: TranslationQuizDirection.translationToSource,
    );

    expect(quiz.items, hasLength(5));
    expect(quiz.items.first.prompt, 'I see a cat.');
    expect(quiz.items.first.expectedAnswer, 'Je vois un chat.');
    expect(quiz.direction, TranslationQuizDirection.translationToSource);
    expect(client.prompts.single, contains('exactly 5 bilingual'));
  });

  test('checks a translation and parses grading JSON', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      jsonEncode({
        'correct': false,
        'feedback': 'Close, but use the plural.',
        'correctedAnswer': 'Nous mangeons.',
        'transcription': 'nu man.ʒɔ̃',
      }),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    final result = await service.checkTranslation(
      prompt: 'We eat.',
      userAnswer: 'Nous mange.',
      expectedAnswer: 'Nous mangeons.',
      direction: TranslationQuizDirection.translationToSource,
    );

    expect(result.isCorrect, isFalse);
    expect(result.feedback, 'Close, but use the plural.');
    expect(result.correctedAnswer, 'Nous mangeons.');
    expect(result.transcription, 'nu man.ʒɔ̃');
  });

  test('rejects incorrect grading JSON without transcription', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      jsonEncode({
        'correct': false,
        'feedback': 'Wrong',
        'correctedAnswer': 'Nous mangeons.',
        'transcription': '',
      }),
      jsonEncode({
        'correct': false,
        'feedback': 'Wrong',
        'correctedAnswer': 'Nous mangeons.',
        'transcription': '',
      }),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    await expectLater(
      () => service.checkTranslation(
        prompt: 'We eat.',
        userAnswer: 'bonjour',
        expectedAnswer: 'Nous mangeons.',
        direction: TranslationQuizDirection.translationToSource,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects incorrect grading JSON without correctedAnswer', () async {
    final settings = AiSettingsService();
    final client = _FakeClient([
      jsonEncode({
        'correct': false,
        'feedback': 'Wrong',
        'correctedAnswer': '',
        'transcription': 'nu man.ʒɔ̃',
      }),
      jsonEncode({
        'correct': false,
        'feedback': 'Wrong',
        'correctedAnswer': '',
        'transcription': 'nu man.ʒɔ̃',
      }),
    ]);
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, client),
    );

    await expectLater(
      () => service.checkTranslation(
        prompt: 'We eat.',
        userAnswer: 'bonjour',
        expectedAnswer: 'Nous mangeons.',
        direction: TranslationQuizDirection.translationToSource,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  testWidgets('quiz sheet defaults to 10 sentences and translation→source', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    final result =
                        await showModalBottomSheet<TranslationQuizOptions>(
                          context: context,
                          isScrollControlled: true,
                          builder:
                              (_) => const TranslationQuizSheet(
                                categories: ['A', 'B'],
                                initialSelection: ['A'],
                              ),
                        );
                    expect(result, isNotNull);
                    expect(result!.sentenceCount, 10);
                    expect(
                      result.direction,
                      TranslationQuizDirection.translationToSource,
                    );
                    expect(result.categories, ['A']);
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    await tester.ensureVisible(find.text('Start quiz'));
    await tester.tap(find.text('Start quiz'));
    await tester.pumpAndSettle();
  });
}
