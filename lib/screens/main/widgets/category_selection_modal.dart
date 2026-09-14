import 'package:flutter/material.dart';

/// Modal bottom sheet allowing the user to pick which categories are active.
class CategorySelectionModal extends StatefulWidget {
  const CategorySelectionModal({
    super.key,
    required this.categories,
    required this.selectedCategories,
    required this.onSelectionChanged,
    required this.selectAllLabel,
    required this.unselectAllLabel,
    this.title = 'Select Categories',
    this.doneLabel = 'Done',
    this.categoryCounts = const {},
    this.selectionSummary,
    this.selectionWarning,
  });

  final List<String> categories;
  final List<String> selectedCategories;
  final Function(List<String>) onSelectionChanged;
  final String selectAllLabel;
  final String unselectAllLabel;
  final String title;
  final String doneLabel;
  final Map<String, int> categoryCounts;
  final String Function(List<String>)? selectionSummary;
  final String? Function(List<String>)? selectionWarning;

  @override
  State<CategorySelectionModal> createState() => _CategorySelectionModalState();
}

class _CategorySelectionModalState extends State<CategorySelectionModal> {
  late List<String> _tempSelection;

  @override
  void initState() {
    super.initState();
    _tempSelection = List.from(widget.selectedCategories);
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        widget.categories.isNotEmpty &&
        widget.categories.every(_tempSelection.contains);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        widget.categories.isEmpty
                            ? null
                            : () {
                              setState(() {
                                _tempSelection =
                                    allSelected
                                        ? <String>[]
                                        : List<String>.from(widget.categories);
                              });
                            },
                    child: Text(
                      allSelected
                          ? widget.unselectAllLabel
                          : widget.selectAllLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.selectionSummary != null) ...[
                Text(widget.selectionSummary!(_tempSelection)),
                const SizedBox(height: 4),
              ],
              if (widget.selectionWarning?.call(_tempSelection)
                  case final warning?)
                Text(
                  warning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.categories.length,
                  itemBuilder: (context, index) {
                    final cat = widget.categories[index];
                    final isSelected = _tempSelection.contains(cat);
                    return CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        widget.categoryCounts.containsKey(cat)
                            ? '$cat (${widget.categoryCounts[cat]})'
                            : cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            if (!_tempSelection.contains(cat)) {
                              _tempSelection.add(cat);
                            }
                          } else {
                            _tempSelection.remove(cat);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  widget.onSelectionChanged(_tempSelection);
                  Navigator.pop(context);
                },
                child: Text(widget.doneLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
