import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/screens/main/widgets/word_tile.dart';

void main() {
  testWidgets('compact tiles preserve scaled long content', (tester) async {
    const longWord =
        'A deliberately long flashcard value that must stay within the tile';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WordTile(
            label: 'Word',
            word: longWord,
            isVisible: true,
            compact: true,
            onToggle: () {},
          ),
        ),
      ),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.minVerticalPadding, 4);
    expect(find.text(longWord), findsOneWidget);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
