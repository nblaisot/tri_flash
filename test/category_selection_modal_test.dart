import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/screens/main/widgets/category_selection_modal.dart';

Widget _app({
  required List<String> categories,
  required List<String> selectedCategories,
  required ValueChanged<List<String>> onSelectionChanged,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        padding: padding,
        viewPadding: padding,
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: CategorySelectionModal(
            categories: categories,
            selectedCategories: selectedCategories,
            selectAllLabel: 'Select all',
            unselectAllLabel: 'Unselect all',
            onSelectionChanged: onSelectionChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('selects every category in source order and waits for Done', (
    tester,
  ) async {
    List<String>? result;
    await tester.pumpWidget(
      _app(
        categories: const ['Zulu', 'Alpha', 'Bravo'],
        selectedCategories: const ['Alpha'],
        onSelectionChanged: (selection) => result = List.from(selection),
      ),
    );

    expect(find.text('Select all'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pump();

    expect(result, isNull);
    expect(find.text('Unselect all'), findsOneWidget);
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((tile) => tile.value == true),
      isTrue,
    );

    await tester.tap(find.text('Done'));
    expect(result, ['Zulu', 'Alpha', 'Bravo']);
  });

  testWidgets('unselects all categories without applying immediately', (
    tester,
  ) async {
    List<String>? result;
    await tester.pumpWidget(
      _app(
        categories: const ['Alpha', 'Bravo'],
        selectedCategories: const ['Alpha', 'Bravo'],
        onSelectionChanged: (selection) => result = List.from(selection),
      ),
    );

    expect(find.text('Unselect all'), findsOneWidget);
    await tester.tap(find.text('Unselect all'));
    await tester.pump();

    expect(result, isNull);
    expect(find.text('Select all'), findsOneWidget);
    await tester.tap(find.text('Done'));
    expect(result, isEmpty);
  });

  testWidgets('disables the bulk action for an empty category list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        categories: const [],
        selectedCategories: const [],
        onSelectionChanged: (_) {},
      ),
    );

    final action = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Select all'),
    );
    expect(action.onPressed, isNull);
  });

  testWidgets('keeps Done above the bottom system inset', (tester) async {
    const bottomInset = 48.0;
    await tester.pumpWidget(
      _app(
        categories: const ['Alpha'],
        selectedCategories: const [],
        onSelectionChanged: (_) {},
        padding: const EdgeInsets.only(bottom: bottomInset),
      ),
    );

    final mediaQuery = tester.widget<MediaQuery>(find.byType(MediaQuery).last);
    final safeBottom = mediaQuery.data.size.height - bottomInset;
    expect(tester.getBottomRight(find.text('Done')).dy, lessThan(safeBottom));
  });
}
