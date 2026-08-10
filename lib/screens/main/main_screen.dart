import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'package:tri_flash/screens/edit_words/edit_words_screen.dart';
import 'package:tri_flash/screens/load_csv/load_csv_screen.dart';
import 'package:tri_flash/screens/main/controllers/main_screen_controller.dart';
import 'package:tri_flash/screens/main/widgets/action_buttons_row.dart';
import 'package:tri_flash/screens/main/widgets/category_selection_modal.dart';
import 'package:tri_flash/screens/main/widgets/display_selection_modal.dart';
import 'package:tri_flash/screens/main/widgets/main_screen_app_bar.dart';
import 'package:tri_flash/screens/main/widgets/onboarding_overlay.dart';
import 'package:tri_flash/screens/main/widgets/word_content_section.dart';
import 'package:tri_flash/screens/settings/settings_screen.dart';
import 'package:tri_flash/services/csv_service.dart';
import 'package:tri_flash/services/tts_service.dart';
import 'package:tri_flash/services/word_service.dart';
import 'package:tri_flash/state/app_state.dart';

/// Main screen that displays the flash cards and top-level actions.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final MainScreenController _controller;

  // Global keys used by the onboarding overlay to highlight UI elements.
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
    _controller = MainScreenController(
      appState: AppState(),
      ttsService: TtsService(),
      wordService: WordService(),
      csvService: CsvService(),
    )..initialise();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final state = _controller.state;

        return Stack(
          children: [
            Scaffold(
              appBar: MainScreenAppBar(
                categoryButtonText: _controller.categoryButtonText,
                displayLabel: state.defaultVisibleLanguage,
                onShowCategorySelection: _showCategorySelection,
                onShowDisplaySelection: _showDisplaySelection,
                onMenuSelected: _handleMenuAction,
                menuButtonKey: _menuButtonKey,
                categoriesButtonKey: _categoriesButtonKey,
                displayButtonKey: _displayButtonKey,
              ),
              body: _buildBody(),
            ),
            if (state.showOnboarding)
              OnboardingOverlay(
                step: state.onboardingStep,
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
                onNext: _controller.advanceOnboarding,
                onComplete: () => _controller.completeOnboarding(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBody() {
    final word = _controller.currentWord;
    final state = _controller.state;

    if (word == null) {
      return const Center(child: Text('No active words available'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0;

        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WordContentSection(
              currentWord: word,
              activeWords: state.activeWords,
              totalWords: state.totalWords,
              showWord: state.showWord,
              showTranscription: state.showTranscription,
              showTranslation: state.showTranslation,
              onToggleWord: _controller.toggleWordVisibility,
              onToggleTranscription: _controller.toggleTranscriptionVisibility,
              onToggleTranslation: _controller.toggleTranslationVisibility,
              onSpeakWord: () => _controller.speakCurrentWord(context),
              wordsCountKey: _wordsCountKey,
              wordTileKey: _wordTileKey,
              ttsButtonKey: _ttsButtonKey,
            ),
            const SizedBox(height: 20),
            MainActionButtons(
              onEdit: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditWordsScreen(
                      initialSearch: word['word'],
                    ),
                  ),
                ).then((_) => _controller.loadSelectedCategories());
              },
              onHide: _controller.toggleCurrentWordActive,
              onDuplicate: _duplicateToSpecialCategory,
              onNext: _controller.pickRandomWord,
              editButtonKey: _editButtonKey,
              hideButtonKey: _hideButtonKey,
              duplicateButtonKey: _duplicateButtonKey,
            ),
          ],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }

  Future<void> _handleMenuAction(String value) async {
    switch (value) {
      case 'edit':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditWordsScreen()),
        );
        await _controller.loadSelectedCategories();
        break;
      case 'load':
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LoadCsvScreen(onCsvLoaded: (csvList) {}),
          ),
        );
        if (result == true) await _controller.loadSelectedCategories();
        break;
      case 'copy_csv':
        final csvData = await _controller.generateCsvExport();
        _copyToClipboard(csvData);
        break;
      case 'settings':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
        await _controller.reloadTtsSettings();
        break;
    }
  }

  Future<void> _duplicateToSpecialCategory() async {
    final success = await _controller.duplicateCurrentWordToSpecialCategory();
    Fluttertoast.showToast(
      msg: success
          ? 'Word duplicated to !! category'
          : 'This word is already in the !! category',
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  Future<void> _copyToClipboard(String csvData) async {
    await Clipboard.setData(ClipboardData(text: csvData));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV data copied to clipboard!')),
    );
  }

  void _showCategorySelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CategorySelectionModal(
        categories: _controller.categories,
        selectedCategories: _controller.selectedCategories,
        onSelectionChanged: (categories) async {
          await _controller.applySelectedCategories(categories);
        },
      ),
    );
  }

  void _showDisplaySelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DisplaySelectionModal(
        currentSelection: _controller.state.defaultVisibleLanguage,
        onSelectionChanged: _controller.setDefaultVisibleLanguage,
      ),
    );
  }
}
