import 'package:csv/csv.dart';

/// Normalizes published Google Sheets links and parses vocabulary TSV data.
class VocabularyImportService {
  const VocabularyImportService._();

  static String normalizePublishedUrl(String rawUrl) {
    final value = rawUrl.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host != 'docs.google.com') return value;

    final segments = [...uri.pathSegments];
    if (segments.isEmpty ||
        (segments.last != 'pubhtml' && segments.last != 'pub')) {
      return value;
    }

    segments[segments.length - 1] = 'pub';
    final query = <String, String>{...uri.queryParameters};
    query['output'] = 'tsv';
    final normalized =
        uri
            .replace(
              pathSegments: segments,
              queryParameters: query,
              fragment: '',
            )
            .toString();
    return normalized.endsWith('#')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  static List<List<String>> parseTsv(String data) {
    final withoutBom = data.replaceFirst('\ufeff', '');
    final leading = withoutBom.trimLeft().toLowerCase();
    if (leading.startsWith('<!doctype html') || leading.startsWith('<html')) {
      throw const FormatException(
        'The URL returned a web page instead of tab-separated vocabulary.',
      );
    }

    final normalized = withoutBom
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final decoded = const CsvToListConverter(
      fieldDelimiter: '\t',
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(normalized);

    final rows =
        decoded
            .where(
              (row) => row.any((value) => value.toString().trim().isNotEmpty),
            )
            .map((row) {
              final fields =
                  row.map((value) => value.toString().trim()).toList();
              while (fields.length < 4) {
                fields.add('');
              }
              return fields.take(4).toList();
            })
            .toList();

    if (rows.isNotEmpty && _looksLikeHeader(rows.first)) {
      rows.removeAt(0);
    }
    rows.removeWhere((row) => row[1].isEmpty);

    if (rows.isEmpty) {
      throw const FormatException('No vocabulary rows were found.');
    }
    return rows;
  }

  static bool _looksLikeHeader(List<String> row) {
    final category = row[0].toLowerCase();
    final word = row[1].toLowerCase();
    return const {'category', 'categorie', 'catégorie'}.contains(category) &&
        const {'word', 'mot', 'vocabulary', 'vocabulaire'}.contains(word);
  }
}
