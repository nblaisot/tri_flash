import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/services/vocabulary_import_service.dart';

void main() {
  test('normalizes a published HTML sheet URL to TSV', () {
    const input =
        'https://docs.google.com/spreadsheets/d/e/example/pubhtml?gid=123&single=true';

    expect(
      VocabularyImportService.normalizePublishedUrl(input),
      'https://docs.google.com/spreadsheets/d/e/example/pub?gid=123&single=true&output=tsv',
    );
  });

  test('keeps the first row when the published sheet has no header', () {
    const input =
        'Arabic 100\tمرحبًا\tmarḥaban\tHello\nArabic 100\tنعم\tnaʿam\tYes\n';

    final rows = VocabularyImportService.parseTsv(input);

    expect(rows, hasLength(2));
    expect(rows.first, ['Arabic 100', 'مرحبًا', 'marḥaban', 'Hello']);
  });

  test('removes a conventional header row', () {
    const input =
        'category\tword\tpronunciation\ttranslation\nFrench\tbonjour\tbɔ̃ʒuʁ\thello\n';

    final rows = VocabularyImportService.parseTsv(input);

    expect(rows, [
      ['French', 'bonjour', 'bɔ̃ʒuʁ', 'hello'],
    ]);
  });

  test('rejects published HTML instead of importing CSS as vocabulary', () {
    expect(
      () => VocabularyImportService.parseTsv('<!DOCTYPE html><style>x</style>'),
      throwsFormatException,
    );
  });
}
