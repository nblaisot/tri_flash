import 'package:csv/csv.dart';
import '../database_helper.dart';

class CsvService {
  Future<String> generateCsvFile() async {
    var dbHelper = DatabaseHelper.instance;
    var records = await dbHelper.queryAllRows();

    List<List<dynamic>> rows = [
      ["Category", "Word", "Transcription", "Translation"]
    ];

    for (var record in records) {
      var map = record.value;
      List<dynamic> row = [
        map['category'].replaceAll('\r', '').replaceAll('\n', ' '),
        map['word'].replaceAll('\r', '').replaceAll('\n', ' '),
        map['transcription'].replaceAll('\r', '').replaceAll('\n', ' '),
        map['translation'].replaceAll('\r', '').replaceAll('\n', ' ')
      ];
      rows.add(row);
    }

    String csv = const ListToCsvConverter(
        fieldDelimiter: '\t',
        eol: '\n'
    ).convert(rows);

    return csv;
  }
}