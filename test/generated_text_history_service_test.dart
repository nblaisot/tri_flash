import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/generated_text_history_service.dart';

void main() {
  test(
    'retains only the latest twenty annotated texts and clears v1',
    () async {
      SharedPreferences.setMockInitialValues({
        'generated_text_history_v1': ['legacy'],
      });
      final database = await databaseFactoryMemory.openDatabase('history.db');
      final service = GeneratedTextHistoryService(
        database: () async => database,
      );

      for (var index = 0; index < 25; index++) {
        await service.add(
          GeneratedText(
            id: '$index',
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
          ),
        );
      }

      final history = await service.load();
      final prefs = await SharedPreferences.getInstance();
      expect(history, hasLength(20));
      expect(history.first.id, '24');
      expect(history.last.id, '5');
      expect(history.first.sourceAnnotations.single.pronunciation, 'sɔːrs');
      expect(prefs.containsKey('generated_text_history_v1'), isFalse);

      await database.close();
    },
  );
}
