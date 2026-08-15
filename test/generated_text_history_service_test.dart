import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/generated_text_history_service.dart';

GeneratedText _item(int index) => GeneratedText(
  id: '$index',
  title: 'Titre $index',
  titleTranslation: 'Title $index',
  source: 'source $index',
  translation: 'translation $index',
  createdAt: DateTime.utc(2026, 1, 1, 0, index),
  categories: const ['test'],
  targetWordCount: 500,
  outsideVocabularyPercent: 5,
  provider: AiProviderType.openAi,
  sourceAnnotations: const [
    WordAnnotation(
      start: 0,
      end: 6,
      surface: 'source',
      pronunciation: 'sɔːrs',
      contextualTranslation: 'source',
    ),
  ],
  translationAnnotations: const [],
);

void main() {
  test('retains only the latest fifty annotated texts and clears v1', () async {
    SharedPreferences.setMockInitialValues({
      'generated_text_history_v1': ['legacy'],
    });
    final database = await databaseFactoryMemory.openDatabase('history.db');
    final service = GeneratedTextHistoryService(database: () async => database);

    for (var index = 0; index < 55; index++) {
      await service.add(_item(index));
    }

    final history = await service.load();
    final prefs = await SharedPreferences.getInstance();
    expect(history, hasLength(50));
    expect(history.first.id, '54');
    expect(history.last.id, '5');
    expect(history.first.title, 'Titre 54');
    expect(history.first.titleTranslation, 'Title 54');
    expect(history.first.sourceAnnotations.single.pronunciation, 'sɔːrs');
    expect(prefs.containsKey('generated_text_history_v1'), isFalse);

    await database.close();
  });

  test('loads legacy entries without titles using body fallbacks', () {
    final text = GeneratedText.fromJson({
      'id': 'legacy',
      'source': 'Un long texte sans titre pour vérifier le repli.',
      'translation': 'A long text without a title for fallback.',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'categories': ['test'],
      'targetWordCount': 40,
      'outsideVocabularyPercent': 5,
      'provider': 'openai',
      'sourceAnnotations': <Map<String, Object>>[],
      'translationAnnotations': <Map<String, Object>>[],
    });

    expect(text.title, startsWith('Un long texte'));
    expect(text.titleTranslation, startsWith('A long text'));
  });
}
