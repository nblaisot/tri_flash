import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tri_flash/services/csv_service.dart';
import 'package:tri_flash/services/tts_service.dart';
import 'package:tri_flash/services/word_service.dart';
import 'package:tri_flash/state/app_state.dart';

/// Coordinates data loading and user actions for [MainScreen].
///
/// Extracting this logic from the widget keeps the UI focused on layout while
/// centralising the sequencing of asynchronous calls. That makes it easier to
/// follow the onboarding flow, database fetches and preference updates.
class MainScreenController extends ChangeNotifier {
  MainScreenController({
    required AppState appState,
    required TtsService ttsService,
    required WordService wordService,
    required CsvService csvService,
  })  : _appState = appState,
        _ttsService = ttsService,
        _wordService = wordService,
        _csvService = csvService;

  final AppState _appState;
  final TtsService _ttsService;
  final WordService _wordService;
  final CsvService _csvService;

  bool _isLoading = true;
  bool _didInitialise = false;

  /// Flag indicating whether asynchronous setup is still in progress.
  bool get isLoading => _isLoading;

  /// Read-only view of the shared app state.
  AppState get state => _appState;

  /// Convenience accessor for the word currently displayed, if any.
  Map<String, dynamic>? get currentWord {
    if (!hasWords) return null;
    return _appState.words[_appState.currentIndex];
  }

  /// Whether there is at least one active word available.
  bool get hasWords =>
      _appState.words.isNotEmpty && _appState.currentIndex >= 0;

  /// Text used in the categories button within the app bar.
  String get categoryButtonText => _wordService.categoryButtonText;

  /// Exposes the available categories for selection components.
  List<String> get categories => _wordService.categories;

  /// Exposes the categories currently selected by the user.
  List<String> get selectedCategories => _wordService.selectedCategories;

  /// Initiates services and loads the initial dataset.
  Future<void> initialise() async {
    if (_didInitialise) return;
    _didInitialise = true;
    _setLoading(true);

    await _ttsService.initialize();
    await _ttsService.loadFromPrefs();
    await _appState.loadSettings();
    await _wordService.initialize();
    await loadSelectedCategories();
    await _checkOnboardingStatus();

    _setLoading(false);
  }

  /// Refresh the text-to-speech service with the persisted preferences.
  Future<void> reloadTtsSettings() async {
    await _ttsService.loadFromPrefs();
  }

  /// Loads the persisted category selection and the associated words.
  Future<void> loadSelectedCategories() async {
    await _wordService.loadSelectedCategories();
    await _loadWords();
  }

  /// Generates CSV data for export.
  Future<String> generateCsvExport() async {
    return _csvService.generateCsvFile();
  }

  /// Updates the default visible language preference.
  void setDefaultVisibleLanguage(String value) {
    _appState.setDefaultVisibleLanguage(value);
    notifyListeners();
  }

  /// Toggles whether the main word text is visible.
  void toggleWordVisibility() {
    _appState.showWord = !_appState.showWord;
    notifyListeners();
  }

  /// Toggles whether the transcription text is visible.
  void toggleTranscriptionVisibility() {
    _appState.showTranscription = !_appState.showTranscription;
    notifyListeners();
  }

  /// Toggles whether the translation text is visible.
  void toggleTranslationVisibility() {
    _appState.showTranslation = !_appState.showTranslation;
    notifyListeners();
  }

  /// Randomises the active word and resets visibility.
  void pickRandomWord() {
    if (_appState.words.isNotEmpty) {
      final int newRandomIndex = Random().nextInt(_appState.words.length);
      _appState.currentIndex = newRandomIndex;
      _appState.resetVisibility();
    } else {
      _appState.currentIndex = -1;
    }
    notifyListeners();
  }

  /// Speaks the current word using the configured TTS engine.
  Future<void> speakCurrentWord(BuildContext context) async {
    final word = currentWord;
    if (word == null) return;
    await _ttsService.speak(word['word'], context: context);
  }

  /// Marks the current word as hidden/visible.
  Future<void> toggleCurrentWordActive() async {
    final word = currentWord;
    if (word == null) return;
    await _wordService.toggleWordActive(word);
    await _loadWords();
  }

  /// Copies the current word into the special review category.
  Future<bool> duplicateCurrentWordToSpecialCategory() async {
    final word = currentWord;
    if (word == null) return false;
    final bool duplicated =
        await _wordService.duplicateToSpecialCategory(word);
    if (duplicated) {
      await loadSelectedCategories();
    }
    return duplicated;
  }

  /// Applies a new category selection.
  Future<void> applySelectedCategories(List<String> categories) async {
    await _wordService.saveSelectedCategories(categories);
    await loadSelectedCategories();
  }

  /// Advances the onboarding overlay by one step.
  void advanceOnboarding() {
    _appState.nextOnboardingStep();
    notifyListeners();
  }

  /// Completes onboarding and persists the flag.
  Future<void> completeOnboarding() async {
    await _appState.completeOnboarding();
    notifyListeners();
  }

  Future<void> _checkOnboardingStatus() async {
    final bool shouldShow = await _appState.shouldShowOnboarding();
    if (shouldShow) {
      _appState.startOnboarding();
    }
  }

  Future<void> _loadWords() async {
    final result = await _wordService.loadWordsFromDatabase();
    _appState.updateWords(
      result['words'],
      result['totalWords'],
      result['activeWords'],
    );
    if (_appState.words.isNotEmpty) {
      pickRandomWord();
    } else {
      _appState.currentIndex = -1;
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
