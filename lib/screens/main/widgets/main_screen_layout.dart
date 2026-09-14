import 'package:flutter/widgets.dart';

/// Spacing and density choices for the main flashcard screen.
///
/// The inner display of foldable devices has enough width to make the primary
/// screen denser without changing its familiar single-column hierarchy.
class MainScreenLayout {
  const MainScreenLayout._({
    required this.isCompactWide,
    required this.appBarControlsHeight,
    required this.appBarControlsTopPadding,
    required this.bodyPadding,
    required this.contentGap,
  });

  static const double foldableBreakpoint = 600;

  factory MainScreenLayout.fromWidth(double width) {
    if (width >= foldableBreakpoint) {
      return const MainScreenLayout._(
        isCompactWide: true,
        appBarControlsHeight: 80,
        appBarControlsTopPadding: 8,
        bodyPadding: EdgeInsets.fromLTRB(24, 12, 24, 80),
        contentGap: 12,
      );
    }

    return const MainScreenLayout._(
      isCompactWide: false,
      appBarControlsHeight: 100,
      appBarControlsTopPadding: 20,
      bodyPadding: EdgeInsets.fromLTRB(16, 24, 16, 112),
      contentGap: 20,
    );
  }

  final bool isCompactWide;
  final double appBarControlsHeight;
  final double appBarControlsTopPadding;
  final EdgeInsets bodyPadding;
  final double contentGap;
}
