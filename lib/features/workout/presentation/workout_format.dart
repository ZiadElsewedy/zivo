/// Formatting shared across the whole workout feature.
///
/// `trimWeight` existed twice — once as `trimWeight` in the live session's
/// format module and once as a file-private `_trimWeight` at the top of the
/// plan editor — with identical bodies. How ZIVO writes a weight is a product
/// decision, and two copies is one too many for a decision to live in.
library;

/// "60" / "22.5" — a weight without a trailing ".0".
String trimWeight(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
