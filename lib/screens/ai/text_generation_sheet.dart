import 'package:flutter/material.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/screens/main/widgets/category_selection_modal.dart';

class TextGenerationOptions {
  const TextGenerationOptions({
    required this.categories,
    required this.targetWordCount,
    required this.outsideVocabularyPercent,
  });

  final List<String> categories;
  final int targetWordCount;
  final int outsideVocabularyPercent;
}

class TextGenerationSheet extends StatefulWidget {
  const TextGenerationSheet({
    required this.categories,
    required this.initialSelection,
    super.key,
  });

  final List<String> categories;
  final List<String> initialSelection;

  @override
  State<TextGenerationSheet> createState() => _TextGenerationSheetState();
}

class _TextGenerationSheetState extends State<TextGenerationSheet> {
  late List<String> _selected;
  double _wordCount = 20;
  double _outsidePercent = 5;

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
      child: Padding(
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
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.text('generateText'),
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
            const SizedBox(height: 12),
            Text('${l10n.text('targetWordCount')}: ${_wordCount.round()}'),
            Slider(
              value: _wordCount,
              min: 1,
              max: 100,
              divisions: 99,
              label: '${_wordCount.round()}',
              onChanged: (value) => setState(() => _wordCount = value),
            ),
            Text('${l10n.text('unknownWords')}: ${_outsidePercent.round()}%'),
            Slider(
              value: _outsidePercent,
              min: 0,
              max: 50,
              divisions: 50,
              label: '${_outsidePercent.round()}%',
              onChanged: (value) => setState(() => _outsidePercent = value),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                        context,
                        TextGenerationOptions(
                          categories: List.unmodifiable(_selected),
                          targetWordCount: _wordCount.round(),
                          outsideVocabularyPercent: _outsidePercent.round(),
                        ),
                      ),
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.text('generate')),
            ),
          ],
        ),
      ),
    );
  }
}
