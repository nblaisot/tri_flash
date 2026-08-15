import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/ai_setup_flow.dart';
import 'package:tri_flash/screens/ai/generated_text_history_screen.dart';
import 'package:tri_flash/screens/ai/generated_text_viewer_screen.dart';
import 'package:tri_flash/screens/ai/text_generation_sheet.dart';
import 'package:tri_flash/screens/ai/translation_quiz_session_screen.dart';
import 'package:tri_flash/screens/ai/translation_quiz_sheet.dart';
import 'package:tri_flash/screens/ai/try_translation_dialog.dart';

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
import 'package:tri_flash/services/ai/ai_generation_service.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/generated_text_history_service.dart';
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
  final AiGenerationService _aiGeneration = AiGenerationService();
  final GeneratedTextHistoryService _history = GeneratedTextHistoryService();
  AiCancellationToken? _activeGeneration;

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
    _activeGeneration?.cancel();
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
              floatingActionButton: FloatingActionButton(
                tooltip: context.l10n.text('ai'),
                onPressed: _showAiActions,
                child: const Icon(Icons.auto_awesome),
              ),
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
        final double minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0;

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
              onGenerateSentence: _generateSentence,
              onTryTranslation: _tryTranslation,
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
                    builder:
                        (context) =>
                            EditWordsScreen(initialSearch: word['word']),
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
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 112),
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
      case 'generate_text':
        await _generateText();
        break;
      case 'translation_quiz':
        await _startTranslationQuiz();
        break;
      case 'text_history':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GeneratedTextHistoryScreen()),
        );
        break;
    }
  }

  Future<void> _tryTranslation() async {
    final word = _controller.currentWord;
    if (word == null) return;
    final prompt = word['word']?.toString().trim() ?? '';
    final expected = word['translation']?.toString().trim() ?? '';
    if (prompt.isEmpty || expected.isEmpty) return;
    if (!await AiSetupFlow.ensureReady(context)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (_) => TryTranslationDialog(
            prompt: prompt,
            expectedAnswer: expected,
            aiGeneration: _aiGeneration,
          ),
    );
  }

  Future<void> _generateSentence() async {
    final word = _controller.currentWord;
    if (word == null) return;
    if (!await AiSetupFlow.ensureReady(context)) return;
    if (!mounted) return;
    _showLoading();
    try {
      final sentence = await _aiGeneration.generateSentence(
        VocabularyEntry.fromMap(word),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(dialogContext.l10n.text('exampleSentence')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dialogContext.l10n.text('sourceText'),
                    style: Theme.of(dialogContext).textTheme.labelLarge,
                  ),
                  SelectableText(sentence.source),
                  const SizedBox(height: 16),
                  Text(
                    dialogContext.l10n.text('transcription'),
                    style: Theme.of(dialogContext).textTheme.labelLarge,
                  ),
                  SelectableText(sentence.transcription),
                  const SizedBox(height: 16),
                  Text(
                    dialogContext.l10n.text('translationText'),
                    style: Theme.of(dialogContext).textTheme.labelLarge,
                  ),
                  SelectableText(sentence.translation),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text:
                            '${sentence.source}\n${sentence.transcription}\n${sentence.translation}',
                      ),
                    );
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(dialogContext.l10n.text('copied')),
                        ),
                      );
                    }
                  },
                  child: Text(dialogContext.l10n.text('copy')),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _generateSentence();
                  },
                  child: Text(dialogContext.l10n.text('regenerate')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(dialogContext.l10n.text('close')),
                ),
              ],
            ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showAiError(error);
    }
  }

  Future<void> _showAiActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(sheetContext.l10n.text('aiActionsTitle')),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_stories),
                  title: Text(sheetContext.l10n.text('generateText')),
                  onTap: () => Navigator.pop(sheetContext, 'generate_text'),
                ),
                ListTile(
                  leading: const Icon(Icons.quiz_outlined),
                  title: Text(sheetContext.l10n.text('translationQuiz')),
                  onTap: () => Navigator.pop(sheetContext, 'translation_quiz'),
                ),
              ],
            ),
          ),
    );
    if (!mounted || action == null) return;
    if (action == 'generate_text') {
      await _generateText();
    } else if (action == 'translation_quiz') {
      await _startTranslationQuiz();
    }
  }

  Future<void> _startTranslationQuiz() async {
    if (!await AiSetupFlow.ensureReady(context)) return;
    if (!mounted) return;
    final options = await showModalBottomSheet<TranslationQuizOptions>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => TranslationQuizSheet(
            categories: _controller.categories,
            initialSelection: _controller.selectedCategories,
          ),
    );
    if (options == null || !mounted) return;
    final maps = await _controller.loadActiveWordsForCategories(
      options.categories,
    );
    if (!mounted) return;
    final vocabulary = maps.map(VocabularyEntry.fromMap).toList();
    if (vocabulary.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.text('noWords'))));
      return;
    }
    final cancellationToken = AiCancellationToken();
    _activeGeneration = cancellationToken;
    final progress = ValueNotifier<AiGenerationProgress>(
      const AiGenerationProgress(AiGenerationStage.generatingQuiz),
    );
    _showGenerationProgress(progress, cancellationToken);
    try {
      final quiz = await _aiGeneration.generateTranslationQuiz(
        availableVocabulary: vocabulary,
        categories: options.categories,
        sentenceCount: options.sentenceCount,
        direction: options.direction,
        cancellationToken: cancellationToken,
        onProgress: (value) => progress.value = value,
      );
      cancellationToken.throwIfCancelled();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TranslationQuizSessionScreen(quiz: quiz),
        ),
      );
    } on AiGenerationCancelled {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('generationCancelled'))),
      );
    } on AiCorpusTooLargeException {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showAiError(context.l10n.text('corpusTooLarge'));
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showAiError(error);
    } finally {
      if (identical(_activeGeneration, cancellationToken)) {
        _activeGeneration = null;
      }
      progress.dispose();
    }
  }

  Future<void> _generateText() async {
    if (!await AiSetupFlow.ensureReady(context)) return;
    if (!mounted) return;
    final options = await showModalBottomSheet<TextGenerationOptions>(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => TextGenerationSheet(
            categories: _controller.categories,
            initialSelection: _controller.selectedCategories,
          ),
    );
    if (options == null || !mounted) return;
    final maps = await _controller.loadActiveWordsForCategories(
      options.categories,
    );
    if (!mounted) return;
    final vocabulary = maps.map(VocabularyEntry.fromMap).toList();
    if (vocabulary.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.text('noWords'))));
      return;
    }
    final allWordMaps = await _controller.loadAllWords();
    if (!mounted) return;
    final annotationVocabulary =
        allWordMaps.map(VocabularyEntry.fromMap).toList();
    final cancellationToken = AiCancellationToken();
    _activeGeneration = cancellationToken;
    final progress = ValueNotifier<AiGenerationProgress>(
      const AiGenerationProgress(AiGenerationStage.generatingText),
    );
    _showGenerationProgress(progress, cancellationToken);
    try {
      final generated = await _aiGeneration.generateText(
        availableVocabulary: vocabulary,
        annotationVocabulary: annotationVocabulary,
        categories: options.categories,
        targetWordCount: options.targetWordCount,
        outsideVocabularyPercent: options.outsideVocabularyPercent,
        cancellationToken: cancellationToken,
        onProgress: (value) => progress.value = value,
      );
      cancellationToken.throwIfCancelled();
      await _history.add(generated);
      if (cancellationToken.isCancelled) {
        await _history.remove(generated.id);
        throw const AiGenerationCancelled();
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GeneratedTextViewerScreen(text: generated),
        ),
      );
    } on AiGenerationCancelled {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('generationCancelled'))),
      );
    } on AiCorpusTooLargeException {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showAiError(context.l10n.text('corpusTooLarge'));
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showAiError(error);
    } finally {
      if (identical(_activeGeneration, cancellationToken)) {
        _activeGeneration = null;
      }
      progress.dispose();
    }
  }

  void _showGenerationProgress(
    ValueNotifier<AiGenerationProgress> progress,
    AiCancellationToken cancellationToken,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            content: ValueListenableBuilder<AiGenerationProgress>(
              valueListenable: progress,
              builder:
                  (context, value, _) => Row(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(width: 20),
                      Expanded(child: Text(_progressLabel(context, value))),
                    ],
                  ),
            ),
            actions: [
              TextButton(
                onPressed: cancellationToken.cancel,
                child: Text(dialogContext.l10n.text('cancel')),
              ),
            ],
          ),
    );
  }

  String _progressLabel(BuildContext context, AiGenerationProgress progress) {
    final values = {
      if (progress.current != null) 'current': progress.current!,
      if (progress.total != null) 'total': progress.total!,
    };
    final key = switch (progress.stage) {
      AiGenerationStage.generatingText => 'generatingBilingualText',
      AiGenerationStage.generatingQuiz => 'generatingTranslationQuiz',
      AiGenerationStage.annotatingSource => 'annotatingSource',
      AiGenerationStage.saving => 'savingGeneratedText',
    };
    return context.l10n.text(key, values);
  }

  void _showLoading() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(child: Text(context.l10n.text('generating'))),
              ],
            ),
          ),
    );
  }

  void _showAiError(Object error) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(context.l10n.text('aiError')),
            content: Text('$error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.text('close')),
              ),
            ],
          ),
    );
  }

  Future<void> _duplicateToSpecialCategory() async {
    final success = await _controller.duplicateCurrentWordToSpecialCategory();
    Fluttertoast.showToast(
      msg:
          success
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
      builder:
          (context) => CategorySelectionModal(
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
      builder:
          (context) => DisplaySelectionModal(
            currentSelection: _controller.state.defaultVisibleLanguage,
            onSelectionChanged: _controller.setDefaultVisibleLanguage,
          ),
    );
  }
}
