import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/generated_text_history_service.dart';

void main() {
  test('retains only the latest twenty generated texts', () async {
    SharedPreferences.setMockInitialValues({});
    final service = GeneratedTextHistoryService();

    for (var index = 0; index < 25; index++) {
      await service.add(
        GeneratedText(
          id: '$index',
          source: 'source $index',
          translation: 'translation $index',
          createdAt: DateTime.utc(2026, 1, 1, 0, index),
          categories: const ['test'],
          targetWordCount: 20,
          outsideVocabularyPercent: 5,
          provider: AiProviderType.openAi,
          vocabulary: const [],
        ),
      );
    }

    final history = await service.load();
    expect(history, hasLength(20));
    expect(history.first.id, '24');
    expect(history.last.id, '5');
  });
}
