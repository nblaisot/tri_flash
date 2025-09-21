import 'package:flutter/material.dart';

class WordTile extends StatelessWidget {
  final String label;
  final String word;
  final bool isVisible;
  final VoidCallback onToggle;
  final Widget? trailing;

  const WordTile({
    Key? key,
    required this.label,
    required this.word,
    required this.isVisible,
    required this.onToggle,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        subtitle: Container(
          height: 48,
          alignment: Alignment.centerLeft,
          child: isVisible
              ? FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              word,
              style: const TextStyle(fontSize: 24, color: Colors.black),
            ),
          )
              : null,
        ),
        trailing: trailing,
        onTap: onToggle,
        tileColor: isVisible ? const Color(0xFFFFE083) : Colors.grey[200],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}