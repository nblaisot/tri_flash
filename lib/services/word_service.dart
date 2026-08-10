import 'package:sembast/sembast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tri_flash/services/database_helper.dart';

/// Business logic around fetching and mutating word entries.
class WordService {
  List<String> categories = [];
  List<String> selectedCategories = [];

  Future<void> initialize() async {
    await DatabaseHelper.instance.checkAndInitialize();
  }

  String get categoryButtonText {
    if (selectedCategories.isEmpty) {
      return 'Select Category';
    } else if (selectedCategories.length == 1) {
      return selectedCategories.first;
    } else {
      return '${selectedCategories.length} selected';
    }
  }

  Future<void> loadSelectedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    selectedCategories = prefs.getStringList('selectedCategories') ?? [];
    await loadCategories();
  }

  Future<void> saveSelectedCategories(List<String> categories) async {
    selectedCategories = categories;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selectedCategories', categories);
  }

  Future<void> loadCategories() async {
    final dbHelper = DatabaseHelper.instance;
    final dbCategories = await dbHelper.queryCategories();

    dbCategories.sort((a, b) {
      if (a == '!!') return -1;
      if (b == '!!') return 1;
      return a.compareTo(b);
    });

    categories = dbCategories;
    selectedCategories =
        selectedCategories.where((cat) => categories.contains(cat)).toList();

    if (selectedCategories.isEmpty && categories.isNotEmpty) {
      selectedCategories = [categories[0]];
    }
  }

  Future<Map<String, dynamic>> loadWordsFromDatabase() async {
    final dbHelper = DatabaseHelper.instance;
    final List<RecordSnapshot<int, Map<String, dynamic>>> records = [];

    for (final category in selectedCategories) {
      final categoryRecords = await dbHelper.queryWordsByCategory(category);
      records.addAll(categoryRecords);
    }

    final words = records
        .map((record) {
          final wordMap = Map<String, dynamic>.from(record.value);
          wordMap['id'] = record.key;
          return wordMap;
        })
        .where((word) => word['isActive'] == 1)
        .toList();

    return {
      'words': words,
      'totalWords': records.length,
      'activeWords': words.length,
    };
  }

  Future<void> toggleWordActive(Map<String, dynamic> word) async {
    final dbHelper = DatabaseHelper.instance;
    final bool currentActive = word['isActive'] == 1;
    await dbHelper.toggleWordActive(word['id'], !currentActive);
  }

  Future<bool> duplicateToSpecialCategory(Map<String, dynamic> word) async {
    final dbHelper = DatabaseHelper.instance;

    final bool exists = await dbHelper.wordExistsInCategory(
      word[DatabaseHelper.columnWord],
      '!!',
    );

    if (!exists) {
      await dbHelper.duplicateWordToSpecialCategory(word, '!!');
      await loadCategories();
      return true;
    }

    return false;
  }
}
