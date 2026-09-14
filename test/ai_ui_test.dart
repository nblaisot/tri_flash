import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/app/app_theme.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/generated_text_viewer_screen.dart';
import 'package:tri_flash/screens/ai/chatgpt_voice_quiz_sheet.dart';
import 'package:tri_flash/screens/ai/text_generation_sheet.dart';

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.light,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  testWidgets('voice quiz clearly opens in the ChatGPT app', (tester) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: ChatGptVoiceQuizSheet(
            categories: ['Food'],
            initialSelection: ['Food'],
          ),
        ),
      ),
    );

    expect(find.text('ChatGPT app voice quiz'), findsOneWidget);
    expect(find.text('Open in the ChatGPT app'), findsOneWidget);
    expect(find.textContaining('Start Voice in ChatGPT'), findsOneWidget);
  });

  testWidgets('generation word count accepts exact 20–500 values', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: TextGenerationSheet(
            categories: ['test'],
            initialSelection: ['test'],
          ),
        ),
      ),
    );

    final field = find.byType(TextFormField);
    expect(field, findsOneWidget);
    await tester.enterText(field, '19');
    await tester.tap(find.text('Generate'));
    await tester.pump();
    expect(find.text('20–500'), findsOneWidget);

    for (final value in ['20', '137', '500']) {
      await tester.enterText(field, value);
      await tester.pump();
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      expect(slider.value, double.parse(value));
    }
  });

  testWidgets('local generation disables an oversized category selection', (
    tester,
  ) async {
    final entries = List.generate(
      41,
      (index) => VocabularyEntry(
        id: index,
        category: 'test',
        word: 'word$index',
        transcription: '',
        translation: 'translation$index',
      ),
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: TextGenerationSheet(
            categories: const ['test'],
            initialSelection: const ['test'],
            vocabularyByCategory: {'test': entries},
            isOnDevice: true,
          ),
        ),
      ),
    );

    expect(find.text('Selected vocabulary: 41 / 40'), findsOneWidget);
    expect(
      find.textContaining('Local text generation is limited'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextFormField), '50');
    await tester.pump();
    expect(find.text('Selected vocabulary: 41 / 100'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed,
      isNotNull,
    );
  });

  testWidgets('viewer makes annotations clickable and clears on toggle', (
    tester,
  ) async {
    final generated = GeneratedText(
      id: '1',
      title: 'Salutation',
      titleTranslation: 'Greeting',
      source: 'Bonjour !',
      translation: 'Hello!',
      createdAt: DateTime.utc(2026),
      categories: const ['test'],
      targetWordCount: 20,
      outsideVocabularyPercent: 5,
      provider: AiProviderType.openAi,
      sourceAnnotations: const [
        WordAnnotation(
          start: 0,
          end: 7,
          surface: 'Bonjour',
          pronunciation: 'bɔ̃.ʒuʁ',
          contextualTranslation: 'Hello',
        ),
      ],
      translationAnnotations: const [
        WordAnnotation(
          start: 0,
          end: 5,
          surface: 'Hello',
          pronunciation: 'həˈloʊ',
          contextualTranslation: 'Bonjour',
        ),
      ],
    );
    await tester.pumpWidget(_app(GeneratedTextViewerScreen(text: generated)));

    final annotatedText = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.textSpan is TextSpan &&
            (widget.textSpan as TextSpan).children?.any(
                  (span) => span is WidgetSpan,
                ) ==
                true &&
            widget.textSpan!.toPlainText(includePlaceholders: false) == ' !',
      ),
    );
    final rootSpan = annotatedText.textSpan as TextSpan;
    final punctuationSpan = rootSpan.children!.last as TextSpan;
    expect(punctuationSpan.style!.color, AppTheme.light.colorScheme.onSurface);

    await tester.tap(find.text('Bonjour'));
    await tester.pump();
    expect(find.textContaining('Pronunciation: bɔ̃.ʒuʁ'), findsOneWidget);
    expect(
      find.textContaining('Contextual translation: Hello'),
      findsOneWidget,
    );

    await tester.tap(find.text('Translation'));
    await tester.pump();
    expect(find.textContaining('Pronunciation: bɔ̃.ʒuʁ'), findsNothing);
  });

  test('theme uses the amber identity', () {
    final scheme = AppTheme.light.colorScheme;
    expect(scheme.primary, const Color(0xFFFFC107));
    expect(scheme.primaryContainer, const Color(0xFFFFE083));
  });
}
