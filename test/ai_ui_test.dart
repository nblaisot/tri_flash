import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/app/app_theme.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/generated_text_viewer_screen.dart';
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

  testWidgets('viewer makes annotations clickable and clears on toggle', (
    tester,
  ) async {
    final generated = GeneratedText(
      id: '1',
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
