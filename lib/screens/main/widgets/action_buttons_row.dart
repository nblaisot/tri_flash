import 'package:flutter/material.dart';

/// Row of action buttons displayed beneath the flash card content.
///
/// The widget remains stateless and simply delegates user interactions back to
/// the parent via callbacks so that navigation/state updates stay in one place
/// (the main screen's state class).
class MainActionButtons extends StatelessWidget {
  const MainActionButtons({
    required this.onEdit,
    required this.onHide,
    required this.onDuplicate,
    required this.onNext,
    required this.editButtonKey,
    required this.hideButtonKey,
    required this.duplicateButtonKey,
    super.key,
  });

  final VoidCallback onEdit;
  final VoidCallback onHide;
  final VoidCallback onDuplicate;
  final VoidCallback onNext;

  final GlobalKey editButtonKey;
  final GlobalKey hideButtonKey;
  final GlobalKey duplicateButtonKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          key: editButtonKey,
          child: IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit word',
            onPressed: onEdit,
          ),
        ),
        Container(
          key: hideButtonKey,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: ElevatedButton(
            onPressed: onHide,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            child: const Text('Hide'),
          ),
        ),
        Container(
          key: duplicateButtonKey,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: ElevatedButton(
            onPressed: onDuplicate,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('!!'),
          ),
        ),
        ElevatedButton(
          onPressed: onNext,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107)),
          child: const Text('Next'),
        ),
      ],
    );
  }
}
