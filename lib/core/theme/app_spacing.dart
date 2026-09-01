/// ZIVO spacing — a 4pt base rhythm.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double base = 16;
  static const double screen = 22; // screen horizontal padding
  static const double l = 24;
  static const double section = 34; // gap between Today sections
}

/// ZIVO corner radii.
abstract final class AppRadius {
  static const double chip = 8;

  /// A filled input box. The hand-rolled fields had drifted to 12 and 14;
  /// 12 was the more common and the one the compact/numeric fields need.
  static const double field = 12;
  static const double card = 20;

  /// The top corner of a modal bottom sheet. One value, because the
  /// hand-rolled sheets had drifted to 24/26/28 and the difference was
  /// visible when one sheet opened over another.
  static const double sheet = 26;
  static const double pill = 999;
}
