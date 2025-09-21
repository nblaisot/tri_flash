import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'category_selection_modal.dart';
import 'display_selection_modal.dart';
import 'word_tile.dart';
import 'onboarding_overlay.dart';
import 'tts_service.dart';
import 'word_service.dart';
import 'csv_service.dart';
import 'app_state.dart';
import 'edit_words_screen.dart';
import 'load_csv_screen.dart';
import 'settings_screen.dart';
import 'package:fluttertoast/fluttertoast.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AppState _appState = AppState();
  final TtsService _ttsService = TtsService();
  final WordService _wordService = WordService();
  final CsvService _csvService = CsvService();

  // GlobalKeys for onboarding
  final GlobalKey _wordsCountKey = GlobalKey();
  final GlobalKey _menuButtonKey = GlobalKey();
  final GlobalKey _categoriesButtonKey = GlobalKey();
  final GlobalKey _wordTileKey = GlobalKey();
  final GlobalKey _displayButtonKey = GlobalKey();
  final GlobalKey _editButtonKey = GlobalKey();
  final GlobalKey _duplicateButtonKey = GlobalKey();
  final GlobalKey _hideButtonKey = GlobalKey();
  final GlobalKey _ttsButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _ttsService.initialize();
    await _ttsService.loadFromPrefs();
    await _appState.loadSettings();
    await _wordService.initialize();
    await _loadSelectedCategories();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    bool shouldShowOnboarding = await _appState.shouldShowOnboarding();
    if (shouldShowOnboarding) {
      setState(() {
        _appState.startOnboarding();
      });
    }
  }

  Future<void> _loadSelectedCategories() async {
    await _wordService.loadSelectedCategories();
    await _loadWords();
    setState(() {});
  }

  Future<void> _loadWords() async {
    var result = await _wordService.loadWordsFromDatabase();
    setState(() {
      _appState.updateWords(result['words'], result['totalWords'], result['activeWords']);
      _pickRandomWord();
    });
  }

  void _pickRandomWord() {
    if (_appState.words.isNotEmpty) {
      int newRandomIndex = Random().nextInt(_appState.words.length);
      setState(() {
        _appState.currentIndex = newRandomIndex;
        _appState.resetVisibility();
      });
    } else {
      setState(() {
        _appState.currentIndex = -1;
      });
    }
  }

  void _handleMenuAction(String value) async {
    switch (value) {
      case 'edit':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditWordsScreen()),
        );
        _loadSelectedCategories();
        break;
      case 'load':
        var result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => LoadCsvScreen(onCsvLoaded: (csvList) {})),
        );
        if (result == true) _loadSelectedCategories();
        break;
      case 'copy_csv':
        String csvData = await _csvService.generateCsvFile();
        _copyToClipboard(csvData);
        break;
      case 'settings':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
        // Pull the latest values straight from SharedPreferences into the service
        await _ttsService.loadFromPrefs();  // ← refresh service from prefs
        break;
    }
  }

  void _copyToClipboard(String csvData) {
    Clipboard.setData(ClipboardData(text: csvData)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV data copied to clipboard!')),
      );
    });
  }

  Future<void> _toggleWordActive() async {
    if (_appState.words.isNotEmpty && _appState.currentIndex >= 0) {
      await _wordService.toggleWordActive(_appState.words[_appState.currentIndex]);
      _loadWords();
    }
  }

  Future<void> _duplicateToSpecialCategory() async {
    if (_appState.words.isEmpty || _appState.currentIndex < 0) return;

    bool success = await _wordService.duplicateToSpecialCategory(
        _appState.words[_appState.currentIndex]
    );

    if (success) {
      Fluttertoast.showToast(
        msg: "Word duplicated to !! category",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    } else {
      Fluttertoast.showToast(
        msg: "This word is already in the !! category",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: _buildAppBar(),
          body: _buildBody(),
        ),
        if (_appState.showOnboarding)
          OnboardingOverlay(
            step: _appState.onboardingStep,
            keys: {
              1: _wordsCountKey,
              2: _menuButtonKey,
              3: _categoriesButtonKey,
              4: _wordTileKey,
              5: _displayButtonKey,
              6: _editButtonKey,
              7: _duplicateButtonKey,
              8: _hideButtonKey,
              9: _ttsButtonKey,
            },
            onNext: () {
              setState(() {
                _appState.nextOnboardingStep();
              });
            },
            onComplete: () async {
              await _appState.completeOnboarding();
              setState(() {});
            },
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Tri Flash'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(100.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          height: 100.0,
          child: Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Categories:", style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 2),
                      Container(
                        key: _categoriesButtonKey,
                        child: ElevatedButton(
                          onPressed: () => _showCategorySelection(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(
                            _wordService.categoryButtonText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Display:", style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 2),
                      Container(
                        key: _displayButtonKey,
                        child: ElevatedButton(
                          onPressed: () => _showDisplaySelection(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(
                            _appState.defaultVisibleLanguage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        Container(
          key: _menuButtonKey,
          child: PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'edit', child: Text('Edit Words')),
              const PopupMenuItem<String>(value: 'load', child: Text('Load words')),
              const PopupMenuItem<String>(value: 'copy_csv', child: Text('Copy DB to Clipboard as tsv')),
              const PopupMenuItem<String>(value: 'settings', child: Text('Settings')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_appState.words.isEmpty || _appState.currentIndex < 0) {
      return const Center(child: Text('No active words available'));
    }

    var currentWord = _appState.words[_appState.currentIndex];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            key: _wordsCountKey,
            child: Text(
              'Words: ${_appState.activeWords} / ${_appState.totalWords}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            key: _wordTileKey,
            child: WordTile(
              label: 'Word',
              word: currentWord['word'],
              isVisible: _appState.showWord,
              onToggle: () => setState(() => _appState.showWord = !_appState.showWord),
              trailing: IconButton(
                key: _ttsButtonKey,
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _ttsService.speak(
                  currentWord['word'],
                  context: context,
                ),
              ),
            ),
          ),
          WordTile(
            label: 'Transcription',
            word: currentWord['transcription'],
            isVisible: _appState.showTranscription,
            onToggle: () => setState(() => _appState.showTranscription = !_appState.showTranscription),
          ),
          WordTile(
            label: 'Translation',
            word: currentWord['translation'],
            isVisible: _appState.showTranslation,
            onToggle: () => setState(() => _appState.showTranslation = !_appState.showTranslation),
          ),
          const SizedBox(height: 20),
          _buildActionButtons(currentWord),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> currentWord) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          key: _editButtonKey,
          child: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditWordsScreen(
                    initialSearch: currentWord['word'],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          key: _hideButtonKey,
          child: ElevatedButton(
            onPressed: _toggleWordActive,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            child: const Text('Hide'),
          ),
        ),
        const SizedBox(width: 20),
        Container(
          key: _duplicateButtonKey,
          child: ElevatedButton(
            onPressed: _duplicateToSpecialCategory,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('!!'),
          ),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: _pickRandomWord,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107)),
          child: const Text('Next'),
        ),
      ],
    );
  }

  void _showCategorySelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CategorySelectionModal(
        categories: _wordService.categories,
        selectedCategories: _wordService.selectedCategories,
        onSelectionChanged: (categories) async {
          await _wordService.saveSelectedCategories(categories);
          await _loadWords();
          setState(() {});
        },
      ),
    );
  }

  void _showDisplaySelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DisplaySelectionModal(
        currentSelection: _appState.defaultVisibleLanguage,
        onSelectionChanged: (value) {
          setState(() {
            _appState.setDefaultVisibleLanguage(value);
          });
        },
      ),
    );
  }
}