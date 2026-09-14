import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/screens/edit_words/controllers/edit_words_controller.dart';
import 'package:tri_flash/screens/edit_words/widgets/edit_words_filter_sheet.dart';

class _FakeEditWordsController extends EditWordsController {
  _FakeEditWordsController({required this.categories, required this.selection});

  final List<String> categories;
  final List<String> selection;
  List<String>? appliedSelection;
  HiddenFilter appliedHiddenFilter = HiddenFilter.all;

  @override
  List<String> get allCategories => List.unmodifiable(categories);

  @override
  List<String> get selectedCategories => List.unmodifiable(selection);

  @override
  HiddenFilter get hiddenFilter => appliedHiddenFilter;

  @override
  void applyHiddenFilter(HiddenFilter filter) {
    appliedHiddenFilter = filter;
  }

  @override
  void applySelectedCategories(List<String> categories) {
    appliedSelection = List.from(categories);
  }
}

Widget _app(
  EditWordsController controller, {
  Size size = const Size(400, 800),
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(size: size, padding: padding, viewPadding: padding),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: EditWordsFilterSheet(controller: controller),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('uses an adaptive bulk action and applies only on Apply', (
    tester,
  ) async {
    final controller = _FakeEditWordsController(
      categories: const ['Zulu', 'Alpha', 'Bravo'],
      selection: const ['Alpha'],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));

    expect(find.text('Select all'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pump();

    expect(controller.appliedSelection, isNull);
    expect(find.text('Unselect all'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    expect(controller.appliedSelection, ['Zulu', 'Alpha', 'Bravo']);
  });

  testWidgets('keeps Apply above a navigation bar on a short landscape view', (
    tester,
  ) async {
    const size = Size(800, 360);
    const bottomInset = 32.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = _FakeEditWordsController(
      categories: const ['Alpha', 'Bravo'],
      selection: const ['Alpha'],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        controller,
        size: size,
        padding: const EdgeInsets.only(bottom: bottomInset),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.text('Apply')).dy,
      lessThan(size.height - bottomInset),
    );
  });
}
