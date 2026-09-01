/// Parsing the numbers a user typed.
///
/// These live here rather than next to a field widget because they are domain
/// logic, not chrome: `parsePositiveDecimal` was defined at the bottom of
/// `diet/presentation/widgets/diet_number_field.dart`, which meant a page
/// wanting to parse a weight had to import a *diet widget* to do it — so most
/// of them didn't, and spelled the parse out by hand instead. Thirteen call
/// sites had independently written
/// `double.tryParse(x.trim().replaceAll(',', '.'))`, and the ones that forgot
/// the `replaceAll` silently rejected every value typed on an Arabic or
/// European keyboard, where the decimal mark is a comma.
library;

/// A decimal the user typed, accepting a comma as the decimal mark.
///
/// Null for anything that isn't a number — a blank field and "abc" are the
/// same thing here.
double? parseDecimal(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// A whole number the user typed. Null for anything that isn't one.
int? parseWhole(String text) => int.tryParse(text.trim());

/// Like [parseDecimal], but null unless the value is strictly positive. Use
/// for a weight, a quantity, or a macro — where zero is not a real answer.
double? parsePositiveDecimal(String text) {
  final parsed = parseDecimal(text);
  return (parsed == null || parsed <= 0) ? null : parsed;
}

/// Like [parseWhole], but null unless the value is strictly positive. Use for
/// calories, reps, or an age.
int? parsePositiveInt(String text) {
  final parsed = parseWhole(text);
  return (parsed == null || parsed <= 0) ? null : parsed;
}
