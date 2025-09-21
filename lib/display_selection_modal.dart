import 'package:flutter/material.dart';

class DisplaySelectionModal extends StatelessWidget {
  final String currentSelection;
  final Function(String) onSelectionChanged;

  const DisplaySelectionModal({
    Key? key,
    required this.currentSelection,
    required this.onSelectionChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            "\"Next\" will display:",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: <Widget>[
                _buildRadioOption(context, "Word"),
                _buildRadioOption(context, "Transcription"),
                _buildRadioOption(context, "Translation"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioOption(BuildContext context, String value) {
    return RadioListTile<String>(
      title: Text(value),
      value: value,
      groupValue: currentSelection,
      activeColor: const Color(0xFFFFC107),
      onChanged: (String? newValue) {
        if (newValue != null) {
          onSelectionChanged(newValue);
          Navigator.pop(context);
        }
      },
    );
  }
}