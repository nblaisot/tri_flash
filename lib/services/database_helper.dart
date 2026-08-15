import 'dart:async';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Detect if running on the web

class DatabaseHelper {
  static const _databaseName = "MyDatabase.db";
  static const _databaseVersion = 1;
  static final store = intMapStoreFactory.store('words_table');

  static const columnId = 'id';
  static const columnCategory = 'category'; // New column
  static const columnWord = 'word';
  static const columnTranscription = 'transcription';
  static const columnTranslation = 'translation';
  static const columnIsActive = 'isActive';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper _instance = DatabaseHelper._privateConstructor();
  static DatabaseHelper get instance => _instance;

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      DatabaseFactory dbFactory = kIsWeb ? databaseFactoryWeb : databaseFactoryIo;
      var dir = kIsWeb ? null : await path_provider.getApplicationDocumentsDirectory();
      var dbPath = kIsWeb ? _databaseName : join(dir!.path, _databaseName);
      var db = await dbFactory.openDatabase(dbPath);
      _database = db;
      return db;
    } catch (e) {
      print("Failed to initialize the database: $e");
      rethrow; // To understand what's happening
    }
  }

  Future<void> insert(Map<String, dynamic> rowData) async {
    try {
      var dbClient = await database;
      // Make sure rowData contains all required fields and none of them are null
      if (rowData[columnWord] == null || rowData[columnTranscription] == null || rowData[columnTranslation] == null) {
        throw Exception("Mandatory fields must not be null");
      }
      await store.add(dbClient, rowData);
      print('row $rowData inserted');
    } catch (e) {
      print('Failed to insert row: $e');
      throw Exception("Failed to insert"); // Rethrow the exception after logging it or handling it
    }
  }

  Future<List<RecordSnapshot<int, Map<String, dynamic>>>> queryAllRows() async {
    try {
      var dbClient = await database;
      var records = await store.find(dbClient);
      if (records.isEmpty) {
        print('No records found');
      }
      return records;
    } catch (e) {
      print('Failed to query all rows: $e');
      throw Exception("Failed to query all rows"); // Rethrow the exception after logging it or handling it
    }
  }

  Future<int> update(Map<String, dynamic> row) async {
    try {
      var dbClient = await database;
      final finder = Finder(filter: Filter.byKey(row[columnId]));
      return await store.update(dbClient, row, finder: finder);
    } catch (e) {
      print('Failed to update row: $e');
      throw Exception("Failed to update row"); // Rethrow the exception after logging it or handling it
    }
  }

  Future<int> delete(int id) async {
    try {
      var dbClient = await database;
      final finder = Finder(filter: Filter.byKey(id));
      return await store.delete(dbClient, finder: finder);
    } catch (e) {
      print('Failed to delete row: $e');
      throw Exception("Failed to delete row"); // Rethrow the exception after logging it or handling it
    }
  }

  Future<void> toggleWordActive(int id, bool isActive) async {
    try {
      var dbClient = await database;
      final finder = Finder(filter: Filter.byKey(id));
      await store.update(dbClient, {columnIsActive: isActive ? 1 : 0}, finder: finder);
    } catch (e) {
      print('Failed to toggle word active status: $e');
      throw Exception("Failed to toggle word active status"); // Rethrow the exception after logging it or handling it
    }
  }

  // Method to query distinct categories
  Future<List<String>> queryCategories() async {
    try {
      var dbClient = await database;
      var records = await store.find(dbClient);
      return records.map((record) => record.value[columnCategory] as String).toSet().toList();
    } catch (e) {
      print('Failed to query categories: $e');
      throw Exception("Failed to query categories"); // Rethrow the exception after logging it or handling it
    }
  }

  // Method to query words by category
  Future<List<RecordSnapshot<int, Map<String, dynamic>>>> queryWordsByCategory(String category) async {
    try {
      var dbClient = await database;
      final finder = Finder(filter: Filter.equals(columnCategory, category));
      return await store.find(dbClient, finder: finder);
    } catch (e) {
      print('Failed to query words by category: $e');
      throw Exception("Failed to query words by category"); // Rethrow the exception after logging it or handling it
    }
  }

  Future<void> clearTable() async {
    try {
      var dbClient = await database;
      await store.delete(dbClient);
    } catch (e) {
      print('Failed to clear table: $e');
      throw Exception("Failed to clear table"); // Rethrow the exception after logging it or handling it
    }
  }

  Future<bool> isDatabaseEmpty() async {
    try {
      var dbClient = await database;
      var records = await store.find(dbClient);
      return records.isEmpty;
    } catch (e) {
      print('Failed to check if database is empty: $e');
      throw Exception("Failed to check if database is empty"); // Rethrow the exception after logging it or handling it
    }
  }

  // New method to check if a word already exists using the word field as a unique key
  Future<bool> wordExists(String word) async {
    try {
      var dbClient = await database;
      final finder = Finder(filter: Filter.equals(columnWord, word));
      final records = await store.find(dbClient, finder: finder);
      return records.isNotEmpty;
    } catch (e) {
      print('Failed to check if word exists: $e');
      throw Exception("Failed to check if word exists");
    }
  }

  // Function to detect if word exists in category
  Future<bool> wordExistsInCategory(String word, String category) async {
    var dbClient = await database;
    final finder = Finder(filter: Filter.and([
      Filter.equals(columnWord, word),
      Filter.equals(columnCategory, category),
    ]));
    final records = await store.find(dbClient, finder: finder);
    return records.isNotEmpty;
  }

  //Special function to duplicate into !! category
  Future<void> duplicateWordToSpecialCategory(Map<String, dynamic> word, String category) async {
    var newWord = Map<String, dynamic>.from(word);
    newWord[columnCategory] = category;
    newWord[columnIsActive] = 1;
    await insert(newWord);
  }

  // Method to check and load data from CSV if the database is empty
  Future<void> checkAndInitialize() async {
    var dbHelper = DatabaseHelper.instance;
    bool isEmpty = await dbHelper.isDatabaseEmpty();
    if (isEmpty) {
      print('Initializing the database with 1 word');
      await dbHelper.insert({
        'category': 'default',
        'word': '欢迎',
        'transcription': 'huān yíng',
        'translation': 'Welcome',
        'isActive': 1
      });
    }
  }
}
