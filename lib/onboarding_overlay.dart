import 'package:flutter/material.dart';

class OnboardingOverlay extends StatelessWidget {
  final int step;
  final Map<int, GlobalKey> keys;
  final VoidCallback onNext;
  final VoidCallback onComplete;

  const OnboardingOverlay({
    Key? key,
    required this.step,
    required this.keys,
    required this.onNext,
    required this.onComplete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tipData = _getTipData(step);
    final highlightKey = keys[step];

    if (highlightKey == null || highlightKey.currentContext == null) {
      // Schedule a rebuild if the target widget isn't laid out yet
      WidgetsBinding.instance.addPostFrameCallback((_) {
        (context as Element).markNeedsBuild();
      });
      return const SizedBox.shrink();
    }

    // Get position and size of target widget
    RenderBox box = highlightKey.currentContext!.findRenderObject() as RenderBox;
    Offset position = box.localToGlobal(Offset.zero);
    Size size = box.size;

    // Calculate tip position
    double screenHeight = MediaQuery.of(context).size.height;
    double estimatedTipHeight = 200;
    double tipTop = _calculateTipPosition(
      position.dy,
      size.height,
      screenHeight,
      estimatedTipHeight,
    );

    return Stack(
      children: [
        // Dark overlay
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.5),
          ),
        ),
        // Highlight border
        Positioned(
          left: position.dx - 4,
          top: position.dy - 4,
          width: size.width + 8,
          height: size.height + 8,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red, width: 3),
            ),
          ),
        ),
        // Tip card
        Positioned(
          left: 16,
          right: 16,
          top: tipTop,
          child: _buildTipCard(tipData),
        ),
      ],
    );
  }

  double _calculateTipPosition(
      double targetY,
      double targetHeight,
      double screenHeight,
      double tipHeight,
      ) {
    if (targetY + targetHeight + tipHeight + 16 > screenHeight) {
      return targetY - tipHeight - 16;
    } else {
      return targetY + targetHeight + 16;
    }
  }

  Widget _buildTipCard(String tipText) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tipText,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
              ),
              onPressed: step < 9 ? onNext : onComplete,
              child: const Text("Next"),
            ),
          ],
        ),
      ),
    );
  }

  String _getTipData(int step) {
    switch (step) {
      case 1:
        return "Welcome to Tri Flash! It starts with only 1 word loaded. It's up to you to add more";
      case 2:
        return "You can either manually add words from the Edit Words screen, or load a whole list from a Google Sheet with Load Words";
      case 3:
        return "The words are organized in categories, that you can select/unselect from here";
      case 4:
        return "The three tiles can be shown / hidden by clicking on them, to reveal the words or sentences";
      case 5:
        return "When getting to the next word, you can define which tile will be the one shown by default with this menu";
      case 6:
        return "You can directly go edit the current word";
      case 7:
        return "With this !! button, you duplicate the current word to the !! category. This will allow to specifically review difficult words";
      case 8:
        return "When you know a word well, you can choose to hide it. You can unhide it in the Edit Words screen";
      case 9:
        return "Tri Flash can pronounce the words for you. The language is detected with the characters, but you can force the language in the Settings. Enjoy Tri Flash!";
      default:
        return "";
    }
  }
}