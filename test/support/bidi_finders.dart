import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/bidi.dart';

/// `find.text`, but blind to the directional isolates `bidi.dart` inserts.
///
/// A run wrapped by `isolate()` — a plan name, an exercise name, anything the
/// user typed — carries U+2068/U+2069 around it. They render as nothing and
/// mean nothing to a reader, but they are real characters, so a plain
/// `find.text('Push · 3 exercises')` misses a widget showing exactly that.
///
/// Use this whenever the string under assertion was composed from user data.
/// A string of pure app copy needs no such help and should keep using
/// `find.text`, which stays the stricter check.
Finder findTextIgnoringBidi(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && stripBidi(w.data!) == text,
  description: 'Text "$text" (ignoring directional isolates)',
);

/// `find.textContaining`, blind to the directional isolates `bidi.dart` adds.
Finder findTextContainingIgnoringBidi(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (stripBidi(w.data ?? '').contains(text) ||
          stripBidi(w.textSpan?.toPlainText() ?? '').contains(text)),
  description: 'Text containing "$text" (ignoring directional isolates)',
);
