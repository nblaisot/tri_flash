import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/vocabulary_matcher.dart';

void main() {
  const short = VocabularyEntry(
    id: 1,
    category: 'test',
    word: 'new',
    transcription: 'nuː',
    translation: 'nouveau',
  );
  const phrase = VocabularyEntry(
    id: 2,
    category: 'test',
    word: 'New York',
    transcription: 'nuː jɔːrk',
    translation: 'New York',
  );

  test('uses longest non-overlapping matches', () {
    final matches = VocabularyMatcher.findMatches(
      'I visited New York and bought something new.',
      [short, phrase],
      translated: false,
    );

    expect(matches, hasLength(2));
    expect(matches.first.entry.id, 2);
    expect(matches.last.entry.id, 1);
  });

  test('uses the first database occurrence for duplicate terms', () {
    const duplicate = VocabularyEntry(
      id: 3,
      category: 'other',
      word: 'new',
      transcription: 'duplicate',
      translation: 'neuf',
    );
    final matches = VocabularyMatcher.findMatches('A new day', [
      short,
      duplicate,
    ], translated: false);

    expect(matches.single.entry.id, 1);
  });

  test('matches translated values in the translated view', () {
    final matches = VocabularyMatcher.findMatches('Quelque chose de nouveau.', [
      short,
    ], translated: true);

    expect(matches.single.entry, short);
  });
}
