import 'package:csv/csv.dart';

import 'package:tri_flash/services/database_helper.dart';

/// Utility for exporting the local database content to a TSV string.
class CsvService {
  Future<String> generateCsvFile() async {
    final dbHelper = DatabaseHelper.instance;
    final records = await dbHelper.queryAllRows();

    final rows = <List<dynamic>>[
      ['Category', 'Word', 'Transcription', 'Translation'],
    ];

    for (final record in records) {
      final map = record.value;
      final row = [
        map['category'].replaceAll('\r', '').replaceAll('\n', ' '),
        map['word'].replaceAll('\r', '').replaceAll('\n', ' '),
        map['transcription'].replaceAll('\r', '').replaceAll('\n', ' '),
        map['translation'].replaceAll('\r', '').replaceAll('\n', ' '),
      ];
      rows.add(row);
    }

    return const ListToCsvConverter(fieldDelimiter: '\t', eol: '\n').convert(rows);
  }
}
