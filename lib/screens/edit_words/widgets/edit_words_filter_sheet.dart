import 'package:flutter/material.dart';

import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/screens/edit_words/controllers/edit_words_controller.dart';

/// Bottom sheet that allows configuring the filters applied to the word list.
class EditWordsFilterSheet extends StatefulWidget {
  const EditWordsFilterSheet({super.key, required this.controller});

  final EditWordsController controller;

  @override
  State<EditWordsFilterSheet> createState() => _EditWordsFilterSheetState();
}

class _EditWordsFilterSheetState extends State<EditWordsFilterSheet> {
  late HiddenFilter _hiddenFilter;
  late Set<String> _selectedCategories;

  @override
  void initState() {
    super.initState();
    _hiddenFilter = widget.controller.hiddenFilter;
    _selectedCategories = widget.controller.selectedCategories.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter list',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    _buildHiddenFilterSection(),
                    const Divider(),
                    _buildCategoryHeader(),
                    const SizedBox(height: 8),
                    _buildCategoriesList(),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _applyFilters,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHiddenFilterSection() {
    return Column(
      children:
          HiddenFilter.values
              .map(
                (option) => RadioListTile<HiddenFilter>(
                  title: Text(option.label),
                  value: option,
                  groupValue: _hiddenFilter,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _hiddenFilter = value);
                  },
                ),
              )
              .toList(),
    );
  }

  Widget _buildCategoryHeader() {
    final categories = widget.controller.allCategories;
    final allSelected =
        categories.isNotEmpty && categories.every(_selectedCategories.contains);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
        TextButton(
          onPressed:
              categories.isEmpty
                  ? null
                  : () {
                    setState(() {
                      _selectedCategories =
                          allSelected ? <String>{} : categories.toSet();
                    });
                  },
          child: Text(
            context.l10n.text(allSelected ? 'unselectAll' : 'selectAll'),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesList() {
    final categories = widget.controller.allCategories;
    return Column(
      children:
          categories
              .map(
                (category) => CheckboxListTile(
                  title: Text(category),
                  value: _selectedCategories.contains(category),
                  onChanged:
                      (checked) => setState(() {
                        if (checked == true) {
                          _selectedCategories.add(category);
                        } else {
                          _selectedCategories.remove(category);
                        }
                      }),
                ),
              )
              .toList(),
    );
  }

  void _applyFilters() {
    widget.controller.applyHiddenFilter(_hiddenFilter);
    widget.controller.applySelectedCategories(_selectedCategories.toList());
    Navigator.pop(context);
  }
}
