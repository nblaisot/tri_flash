import 'package:sembast/sembast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/database_helper.dart';

class GeneratedTextHistoryService {
  GeneratedTextHistoryService({Future<Database> Function()? database})
    : _database = database ?? (() => DatabaseHelper.instance.database);

  static const maxItems = 20;
  static const _legacyKey = 'generated_text_history_v1';
  static const _migrationKey = 'generated_text_history_v2_migrated';
  static final _store = stringMapStoreFactory.store(
    'generated_text_history_v2',
  );

  final Future<Database> Function() _database;

  Future<List<GeneratedText>> load() async {
    await _removeLegacyHistory();
    final database = await _database();
    final records = await _store.find(
      database,
      finder: Finder(sortOrders: [SortOrder('createdAt', false)]),
    );
    final items = <GeneratedText>[];
    for (final record in records) {
      try {
        items.add(GeneratedText.fromJson(record.value));
      } catch (_) {
        await _store.record(record.key).delete(database);
      }
    }
    return items;
  }

  Future<void> add(GeneratedText item) async {
    await _removeLegacyHistory();
    final database = await _database();
    await database.transaction((transaction) async {
      await _store.record(item.id).put(transaction, item.toJson());
      final records = await _store.find(
        transaction,
        finder: Finder(sortOrders: [SortOrder('createdAt', false)]),
      );
      for (final record in records.skip(maxItems)) {
        await _store.record(record.key).delete(transaction);
      }
    });
  }

  Future<void> clear() async {
    await _store.delete(await _database());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyKey);
  }

  Future<void> remove(String id) async {
    await _store.record(id).delete(await _database());
  }

  Future<void> _removeLegacyHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationKey) == true) return;
    await prefs.remove(_legacyKey);
    await prefs.setBool(_migrationKey, true);
  }
}
