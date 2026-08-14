/// Money is always stored as integer minor units (e.g. piastres for EGP) to
/// avoid floating-point rounding. These helpers format for display only.
String formatAmount(int minor) {
  final major = minor / 100;
  return minor % 100 == 0
      ? major.toStringAsFixed(0)
      : major.toStringAsFixed(2);
}

/// Parses typed keypad digits (e.g. "12.5") into minor units.
int parseMinor(String digits) {
  if (digits.isEmpty) return 0;
  final value = double.tryParse(digits) ?? 0;
  return (value * 100).round();
}
