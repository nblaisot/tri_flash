import 'package:flutter/material.dart';

/// Card widget that toggles visibility of a piece of information (word, transcription, translation).
class WordTile extends StatelessWidget {
  const WordTile({
    super.key,
    required this.label,
    required this.word,
    required this.isVisible,
    required this.onToggle,
    this.trailing,
  });

  final String label;
  final String word;
  final bool isVisible;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 16,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Container(
          height: 48,
          alignment: Alignment.centerLeft,
          child:
              isVisible
                  ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      word,
                      style: TextStyle(
                        fontSize: 24,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                  : null,
        ),
        trailing: trailing,
        onTap: onToggle,
        tileColor:
            isVisible
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
