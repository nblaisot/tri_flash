import 'package:flutter/material.dart';

class CategorySelectionModal extends StatefulWidget {
  final List<String> categories;
  final List<String> selectedCategories;
  final Function(List<String>) onSelectionChanged;

  const CategorySelectionModal({
    Key? key,
    required this.categories,
    required this.selectedCategories,
    required this.onSelectionChanged,
  }) : super(key: key);

  @override
  _CategorySelectionModalState createState() => _CategorySelectionModalState();
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            "Select Categories",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: widget.categories.length,
              itemBuilder: (context, index) {
                String cat = widget.categories[index];
                bool isSelected = _tempSelection.contains(cat);
                return CheckboxListTile(
                  activeColor: const Color(0xFFFFC107),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    cat,
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
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }
}