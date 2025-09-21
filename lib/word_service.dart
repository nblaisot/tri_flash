import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import 'package:sembast/sembast.dart';

class WordService {
  List<String> categories = [];
  List<String> selectedCategories = [];

  Future<void> initialize() async {
    await DatabaseHelper.instance.checkAndInitialize();
  }

  String get categoryButtonText {
    if (selectedCategories.isEmpty) {
      return "Select Category";
    } else if (selectedCategories.length == 1) {
      return selectedCategories.first;
    } else {
      return "${selectedCategories.length} selected";
    }
  }

  Future<void> loadSelectedCategories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    selectedCategories = prefs.getStringList('selectedCategories') ?? [];
    await loadCategories();
  }

  Future<void> saveSelectedCategories(List<String> categories) async {
    selectedCategories = categories;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selectedCategories', categories);
  }

  Future<void> loadCategories() async {
    var dbHelper = DatabaseHelper.instance;
    var dbCategories = await dbHelper.queryCategories();

    dbCategories.sort((a, b) {
      if (a == '!!') return -1;
      if (b == '!!') return 1;
      return a.compareTo(b);
    });

    categories = dbCategories;
    selectedCategories = selectedCategories.where((cat) => categories.contains(cat)).toList();

    if (selectedCategories.isEmpty && categories.isNotEmpty) {
      selectedCategories = [categories[0]];
    }
  }

  Future<Map<String, dynamic>> loadWordsFromDatabase() async {
    var dbHelper = DatabaseHelper.instance;
    List<RecordSnapshot<int, Map<String, dynamic>>> records = [];

    for (String category in selectedCategories) {
      var categoryRecords = await dbHelper.queryWordsByCategory(category);
      records.addAll(categoryRecords);
    }

    var words = records.map((record) {
      var wordMap = Map<String, dynamic>.from(record.value);
      wordMap['id'] = record.key;
      return wordMap;
    }).where((word) => word['isActive'] == 1).toList();

    return {
      'words': words,
      'totalWords': records.length,
      'activeWords': words.length,
    };
  }

  Future<void> toggleWordActive(Map<String, dynamic> word) async {
    var dbHelper = DatabaseHelper.instance;
    bool currentActive = word['isActive'] == 1;
    await dbHelper.toggleWordActive(word['id'], !currentActive);
  }

  Future<bool> duplicateToSpecialCategory(Map<String, dynamic> word) async {
    var dbHelper = DatabaseHelper.instance;

    bool exists = await dbHelper.wordExistsInCategory(
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