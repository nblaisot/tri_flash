import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:tri_flash/screens/main/widgets/main_screen_layout.dart';

void main() {
  test('uses the existing phone layout below the foldable breakpoint', () {
    final layout = MainScreenLayout.fromWidth(599);

    expect(layout.isCompactWide, isFalse);
    expect(layout.appBarControlsHeight, 100);
    expect(layout.bodyPadding, const EdgeInsets.fromLTRB(16, 24, 16, 112));
  });

  test('uses the compact top-aligned layout at foldable width', () {
    final layout = MainScreenLayout.fromWidth(600);

    expect(layout.isCompactWide, isTrue);
    expect(layout.appBarControlsHeight, 80);
    expect(layout.bodyPadding, const EdgeInsets.fromLTRB(24, 12, 24, 80));
    expect(layout.contentGap, 12);
  });
}
