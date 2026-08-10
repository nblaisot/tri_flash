import 'package:flutter/material.dart';
import 'package:tri_flash/screens/main/widgets/word_tile.dart';

/// Displays the selected word along with transcription/translation toggles.
///
/// This widget keeps the visual structure of the main column isolated from the
/// state management in [_MainScreenState].
class WordContentSection extends StatelessWidget {
  const WordContentSection({
    required this.currentWord,
    required this.activeWords,
    required this.totalWords,
    required this.showWord,
    required this.showTranscription,
    required this.showTranslation,
    required this.onToggleWord,
    required this.onToggleTranscription,
    required this.onToggleTranslation,
    required this.onSpeakWord,
    required this.wordsCountKey,
    required this.wordTileKey,
    required this.ttsButtonKey,
    super.key,
  });

  final Map<String, dynamic> currentWord;
  final int activeWords;
  final int totalWords;

  final bool showWord;
  final bool showTranscription;
  final bool showTranslation;

  final VoidCallback onToggleWord;
  final VoidCallback onToggleTranscription;
  final VoidCallback onToggleTranslation;
  final VoidCallback onSpeakWord;

  final GlobalKey wordsCountKey;
  final GlobalKey wordTileKey;
  final GlobalKey ttsButtonKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          key: wordsCountKey,
          child: Text(
            'Words: $activeWords / $totalWords',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          key: wordTileKey,
          child: WordTile(
            label: 'Word',
            word: currentWord['word'],
            isVisible: showWord,
            onToggle: onToggleWord,
            trailing: IconButton(
              key: ttsButtonKey,
              icon: const Icon(Icons.play_arrow),
              onPressed: onSpeakWord,
            ),
          ),
        ),
        WordTile(
          label: 'Transcription',
          word: currentWord['transcription'],
          isVisible: showTranscription,
          onToggle: onToggleTranscription,
        ),
        WordTile(
          label: 'Translation',
          word: currentWord['translation'],
          isVisible: showTranslation,
          onToggle: onToggleTranslation,
        ),
      ],
    );
  }
}
