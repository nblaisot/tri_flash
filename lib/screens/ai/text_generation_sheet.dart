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
  final _formKey = GlobalKey<FormState>();
  late List<String> _selected;
  double _wordCount = 20;
  double _outsidePercent = 5;
  late final TextEditingController _wordCountController;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelection);
    _wordCountController = TextEditingController(text: '20');
  }

  @override
  void dispose() {
    _wordCountController.dispose();
    super.dispose();
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
      child: Form(
        key: _formKey,
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
                    color: Theme.of(context).colorScheme.outlineVariant,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.text('targetWordCount')),
                        Slider(
                          value: _wordCount,
                          min: 20,
                          max: 500,
                          divisions: 48,
                          label: '${_wordCount.round()}',
                          onChanged: (value) {
                            setState(() => _wordCount = value);
                            _wordCountController.text = '${value.round()}';
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    child: TextFormField(
                      controller: _wordCountController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(isDense: true),
                      validator: (value) {
                        final number = int.tryParse(value ?? '');
                        if (number == null || number < 20 || number > 500) {
                          return l10n.text('wordCountRange');
                        }
                        return null;
                      },
                      onChanged: (value) {
                        final number = int.tryParse(value);
                        if (number != null && number >= 20 && number <= 500) {
                          setState(() => _wordCount = number.toDouble());
                        }
                      },
                    ),
                  ),
                ],
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
                        : () {
                          if (!_formKey.currentState!.validate()) return;
                          Navigator.pop(
                            context,
                            TextGenerationOptions(
                              categories: List.unmodifiable(_selected),
                              targetWordCount: int.parse(
                                _wordCountController.text,
                              ),
                              outsideVocabularyPercent: _outsidePercent.round(),
                            ),
                          );
                        },
                icon: const Icon(Icons.auto_awesome),
                label: Text(l10n.text('generate')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
