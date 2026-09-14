import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/chatgpt_voice_quiz_service.dart';

void main() {
  const vocabulary = [
    VocabularyEntry(
      id: 1,
      category: 'Food',
      word: 'pomme',
      transcription: 'pɔm',
      translation: 'apple',
    ),
    VocabularyEntry(
      id: 2,
      category: 'Travel',
      word: 'gare',
      transcription: '',
      translation: 'station',
    ),
  ];

  test('builds a voice-teacher prompt with every selected word', () {
    final prompt = ChatGptVoiceQuizService().buildPrompt(
      vocabulary: vocabulary,
      categories: const ['Food', 'Travel'],
      direction: TranslationQuizDirection.translationToSource,
      sourceLanguage: 'French',
      translationLanguage: 'English',
    );

    expect(prompt, contains('language of the clues/questions is English'));
    expect(prompt, contains('answer in French'));
    expect(prompt, contains('Food, Travel'));
    expect(prompt, contains('"word":"pomme"'));
    expect(prompt, contains('"translation":"station"'));
    expect(prompt, contains('exactly one word at a time'));
    expect(prompt, contains('If I ask for a hint'));
    expect(prompt, contains('native-like pronunciation'));
    expect(prompt, contains('lexical tones or vowel length'));
    expect(prompt, contains('focused review quiz'));
    expect(prompt, contains('only the words I missed'));
    expect(prompt, contains('Begin immediately'));
  });

  test('reverses prompt and answer languages for the other direction', () {
    final prompt = ChatGptVoiceQuizService().buildPrompt(
      vocabulary: vocabulary,
      categories: const ['Food', 'Travel'],
      direction: TranslationQuizDirection.sourceToTranslation,
      sourceLanguage: 'French',
      translationLanguage: 'English',
    );

    expect(prompt, contains('language of the clues/questions is French'));
    expect(prompt, contains('answer in English'));
  });
}
