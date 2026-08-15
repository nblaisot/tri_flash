import 'package:flutter/material.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/main/widgets/category_selection_modal.dart';

class TranslationQuizOptions {
  const TranslationQuizOptions({
    required this.categories,
    required this.sentenceCount,
    required this.direction,
  });

  final List<String> categories;
  final int sentenceCount;
  final TranslationQuizDirection direction;
}

class TranslationQuizSheet extends StatefulWidget {
  const TranslationQuizSheet({
    required this.categories,
    required this.initialSelection,
    super.key,
  });

  final List<String> categories;
  final List<String> initialSelection;

  static const sentenceCounts = [5, 10, 15, 20];

  @override
  State<TranslationQuizSheet> createState() => _TranslationQuizSheetState();
}

class _TranslationQuizSheetState extends State<TranslationQuizSheet> {
  late List<String> _selected;
  int _sentenceCount = 10;
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
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
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
              l10n.text('translationQuiz'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
            Text(l10n.text('sentenceCount')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in TranslationQuizSheet.sentenceCounts)
                  ChoiceChip(
                    label: Text('$count'),
                    selected: _sentenceCount == count,
                    onSelected: (_) => setState(() => _sentenceCount = count),
                  ),
              ],
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
                      : () {
                        Navigator.pop(
                          context,
                          TranslationQuizOptions(
                            categories: List.unmodifiable(_selected),
                            sentenceCount: _sentenceCount,
                            direction: _direction,
                          ),
                        );
                      },
              icon: const Icon(Icons.quiz_outlined),
              label: Text(l10n.text('startQuiz')),
            ),
          ],
        ),
      ),
    );
  }
}
