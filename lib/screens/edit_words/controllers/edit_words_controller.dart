import 'package:flutter/material.dart';

import 'package:tri_flash/services/database_helper.dart';

/// Filters available in the edit words screen.
enum HiddenFilter { all, hiddenOnly, visibleOnly }

extension HiddenFilterLabel on HiddenFilter {
  String get label {
    switch (this) {
      case HiddenFilter.all:
        return 'All';
      case HiddenFilter.hiddenOnly:
        return 'Hidden';
      case HiddenFilter.visibleOnly:
        return 'Non-hidden';
    }
  }
}

/// Encapsulates the data loading, filtering and CRUD logic for
/// [EditWordsScreen].
class EditWordsController extends ChangeNotifier {
  EditWordsController({String initialSearch = ''})
      : _dbHelper = DatabaseHelper.instance,
        searchController = TextEditingController(text: initialSearch);

  final DatabaseHelper _dbHelper;

  /// Controller bound to the search field.
  final TextEditingController searchController;

  List<Map<String, dynamic>> _words = [];
  List<Map<String, dynamic>> _filteredWords = [];
  List<String> _allCategories = [];
  List<String> _selectedCategories = [];
  HiddenFilter _hiddenFilter = HiddenFilter.all;
  bool _isLoading = true;

  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get filteredWords => List.unmodifiable(_filteredWords);
  List<String> get allCategories => List.unmodifiable(_allCategories);
  List<String> get selectedCategories => List.unmodifiable(_selectedCategories);
  HiddenFilter get hiddenFilter => _hiddenFilter;

  /// Bootstraps the controller by loading categories and existing words.
  Future<void> initialise() async {
    await _loadCategories();
    await _loadWords();
    _applyFilters();
    _setLoading(false);
  }

  /// Refreshes the dataset from disk while preserving filter settings.
  Future<void> refresh() async {
    await _loadCategories();
    await _loadWords();
    _applyFilters();
    notifyListeners();
  }

  /// Updates the free-text search query.
  void updateQuery(String query) {
    _applyFilters(query: query);
    notifyListeners();
  }

  /// Applies a new hidden filter selection.
  void applyHiddenFilter(HiddenFilter filter) {
    _hiddenFilter = filter;
    _applyFilters();
    notifyListeners();
  }

  /// Applies the provided category selection.
  void applySelectedCategories(List<String> categories) {
    _selectedCategories = List.from(categories);
    _applyFilters();
    notifyListeners();
  }

  /// Clears the category selection.
  void clearCategorySelection() {
    applySelectedCategories([]);
  }

  /// Selects all known categories.
  void selectAllCategories() {
    applySelectedCategories(_allCategories);
  }

  /// Inserts a new word into the database.
  Future<void> createWord(Map<String, dynamic> newWord) async {
    await _dbHelper.insert(newWord);
    await refresh();
  }

  /// Updates an existing word.
  Future<void> updateWord(Map<String, dynamic> word) async {
    await _dbHelper.update(word);
    await refresh();
  }

  /// Deletes a word from the database.
  Future<void> deleteWord(int id) async {
    await _dbHelper.delete(id);
    await refresh();
  }

  /// Toggles whether the word is active.
  Future<void> toggleWordActive(int id, bool isActive) async {
    await _dbHelper.toggleWordActive(id, !isActive);
    await refresh();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await _dbHelper.queryCategories();
    categories.sort((a, b) {
      if (a == '!!') return -1;
      if (b == '!!') return 1;
      return a.compareTo(b);
    });

    _allCategories = categories;
    if (_selectedCategories.isEmpty) {
      _selectedCategories = List.from(categories);
    } else {
      _selectedCategories = _selectedCategories
          .where((category) => categories.contains(category))
          .toList();
    }
  }

  Future<void> _loadWords() async {
    final snapshots = await _dbHelper.queryAllRows();
    _words = snapshots.map((snapshot) {
      final wordMap = Map<String, dynamic>.from(snapshot.value);
      wordMap['id'] = snapshot.key;
      return wordMap;
    }).toList();
  }

  void _applyFilters({String? query}) {
    final lowerQuery = query ?? searchController.text;
    final queryLower = lowerQuery.toLowerCase();

    _filteredWords = _words.where((word) {
      final matchesQuery = queryLower.isEmpty ||
          word['category'].toLowerCase().contains(queryLower) ||
          word['word'].toLowerCase().contains(queryLower) ||
          word['transcription'].toLowerCase().contains(queryLower) ||
          word['translation'].toLowerCase().contains(queryLower);

      final isActive = word['isActive'] == 1;
      final matchesHidden = _hiddenFilter == HiddenFilter.all ||
          (_hiddenFilter == HiddenFilter.hiddenOnly && !isActive) ||
          (_hiddenFilter == HiddenFilter.visibleOnly && isActive);

      final matchesCategory = _selectedCategories.isEmpty ||
          _selectedCategories.contains(word['category']);

      return matchesQuery && matchesHidden && matchesCategory;
    }).toList();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
