import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/try_translation_dialog.dart';
import 'package:tri_flash/services/ai/ai_generation_service.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';

class _FakeClient implements AiProviderClient {
  _FakeClient(this.responses);

  final List<Object> responses;
  var calls = 0;

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
    AiResponseSchema? responseSchema,
  }) async {
    cancellationToken?.throwIfCancelled();
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

  Future<void> pumpDialog(
    WidgetTester tester, {
    required AiGenerationService service,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TryTranslationDialog(
            prompt: 'chat',
            expectedAnswer: 'cat',
            direction: TranslationQuizDirection.sourceToTranslation,
            aiGeneration: service,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the source prompt', (tester) async {
    final settings = AiSettingsService();
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(settings, _FakeClient(const [])),
    );
    await pumpDialog(tester, service: service);

    expect(find.text('Practice translation'), findsOneWidget);
    expect(find.text('chat'), findsOneWidget);
    expect(find.text('Translate this'), findsOneWidget);
  });

  testWidgets('shows correct feedback after a successful check', (
    tester,
  ) async {
    final settings = AiSettingsService();
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(
        settings,
        _FakeClient([
          jsonEncode({
            'correct': true,
            'feedback': 'Nice work.',
            'correctedAnswer': '',
            'transcription': '',
          }),
        ]),
      ),
    );
    await pumpDialog(tester, service: service);

    await tester.enterText(find.byType(TextField), 'cat');
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();

    expect(find.text('Correct'), findsOneWidget);
    expect(find.text('Nice work.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('shows suggested correction when incorrect', (tester) async {
    final settings = AiSettingsService();
    final service = AiGenerationService(
      settings: settings,
      clientFactory: _FakeFactory(
        settings,
        _FakeClient([
          jsonEncode({
            'correct': false,
            'feedback': 'Close, but use the animal sense.',
            'correctedAnswer': 'cat',
            'transcription': 'kæt',
          }),
        ]),
      ),
    );
    await pumpDialog(tester, service: service);

    await tester.enterText(find.byType(TextField), 'chat room');
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();

    expect(find.text('Not quite'), findsOneWidget);
    expect(find.text('Close, but use the animal sense.'), findsOneWidget);
    expect(find.text('Suggested correction'), findsOneWidget);
    expect(find.text('cat'), findsWidgets);
    expect(find.text('Transcription'), findsOneWidget);
    expect(find.text('kæt'), findsOneWidget);
  });
}
