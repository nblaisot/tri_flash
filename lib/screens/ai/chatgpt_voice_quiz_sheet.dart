import 'package:flutter/material.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/main/widgets/category_selection_modal.dart';

class ChatGptVoiceQuizOptions {
  const ChatGptVoiceQuizOptions({
    required this.categories,
    required this.direction,
  });

  final List<String> categories;
  final TranslationQuizDirection direction;
}

class ChatGptVoiceQuizSheet extends StatefulWidget {
  const ChatGptVoiceQuizSheet({
    required this.categories,
    required this.initialSelection,
    super.key,
  });

  final List<String> categories;
  final List<String> initialSelection;

  @override
  State<ChatGptVoiceQuizSheet> createState() => _ChatGptVoiceQuizSheetState();
}

class _ChatGptVoiceQuizSheetState extends State<ChatGptVoiceQuizSheet> {
  late List<String> _selected;
  TranslationQuizDirection _direction =
      TranslationQuizDirection.translationToSource;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelection);
  }

  Future<void> _chooseCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => CategorySelectionModal(
            categories: widget.categories,
            selectedCategories: _selected,
            title: context.l10n.text('selectCategories'),
            doneLabel: context.l10n.text('done'),
            selectAllLabel: context.l10n.text('selectAll'),
            unselectAllLabel: context.l10n.text('unselectAll'),
            onSelectionChanged: (selection) {
              setState(() => _selected = List.from(selection));
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.text('chatGptVoiceQuiz'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(l10n.text('chatGptVoiceQuizHelp')),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _chooseCategories,
              icon: const Icon(Icons.category_outlined),
              label: Text(
                _selected.isEmpty
                    ? l10n.text('selectCategories')
                    : _selected.join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.text('quizDirection')),
            RadioGroup<TranslationQuizDirection>(
              groupValue: _direction,
              onChanged: (value) {
                if (value != null) setState(() => _direction = value);
              },
              child: Column(
                children: [
                  RadioListTile<TranslationQuizDirection>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.text('directionTranslationToSource')),
                    value: TranslationQuizDirection.translationToSource,
                  ),
                  RadioListTile<TranslationQuizDirection>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.text('directionSourceToTranslation')),
                    value: TranslationQuizDirection.sourceToTranslation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                        context,
                        ChatGptVoiceQuizOptions(
                          categories: List.unmodifiable(_selected),
                          direction: _direction,
                        ),
                      ),
              icon: const Icon(Icons.open_in_new),
              label: Text(l10n.text('openChatGptApp')),
            ),
          ],
        ),
      ),
    );
  }
}
