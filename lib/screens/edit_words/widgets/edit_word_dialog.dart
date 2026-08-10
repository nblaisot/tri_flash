import 'package:flutter/material.dart';

import 'package:tri_flash/screens/edit_words/controllers/edit_words_controller.dart';

/// Dialog that allows creating or editing a single word entry.
class EditWordDialog extends StatefulWidget {
  const EditWordDialog({
    super.key,
    required this.controller,
    this.initialWord,
  });

  final EditWordsController controller;
  final Map<String, dynamic>? initialWord;

  bool get isNew => initialWord == null;

  @override
  State<EditWordDialog> createState() => _EditWordDialogState();
}

class _EditWordDialogState extends State<EditWordDialog> {
  late final TextEditingController _categoryController;
  late final TextEditingController _wordController;
  late final TextEditingController _transcriptionController;
  late final TextEditingController _translationController;
  late bool _isHidden;

  @override
  void initState() {
    super.initState();
    _categoryController =
        TextEditingController(text: widget.initialWord?['category'] ?? '');
    _wordController =
        TextEditingController(text: widget.initialWord?['word'] ?? '');
    _transcriptionController = TextEditingController(
      text: widget.initialWord?['transcription'] ?? '',
    );
    _translationController = TextEditingController(
      text: widget.initialWord?['translation'] ?? '',
    );
    _isHidden = widget.initialWord?['isActive'] == 0;
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _wordController.dispose();
    _transcriptionController.dispose();
    _translationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isNew ? 'Create New Word' : 'Edit Word'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            TextField(
              controller: _wordController,
              decoration: const InputDecoration(labelText: 'Word'),
            ),
            TextField(
              controller: _transcriptionController,
              decoration: const InputDecoration(labelText: 'Transcription'),
            ),
            TextField(
              controller: _translationController,
              decoration: const InputDecoration(labelText: 'Translation'),
            ),
            if (!widget.isNew)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Hidden'),
                  Switch(
                    activeColor: const Color(0xFFFFC107),
                    value: _isHidden,
                    onChanged: (value) => setState(() => _isHidden = value),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        if (!widget.isNew)
          TextButton(
            onPressed: () async {
              final id = widget.initialWord!['id'] as int;
              await widget.controller.deleteWord(id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        TextButton(
          onPressed: () async {
            final payload = <String, dynamic>{
              'category': _categoryController.text,
              'word': _wordController.text,
              'transcription': _transcriptionController.text,
              'translation': _translationController.text,
              'isActive': _isHidden ? 0 : 1,
            };

            if (widget.isNew) {
              await widget.controller.createWord(payload);
            } else {
              payload['id'] = widget.initialWord!['id'];
              await widget.controller.updateWord(payload);
            }

            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.isNew ? 'Create' : 'Update'),
        ),
      ],
    );
  }
}
