/// Keeping a technical run readable when the paragraph around it is Arabic.
///
/// A string like `3 × 8–10 · rest 1:30` is not prose: it is a little diagram
/// made of numbers, ranges, units and separators, and every character in it is
/// either a digit or *bidi-neutral*. Dropped into a right-to-left paragraph,
/// the Unicode bidirectional algorithm does what it is supposed to do with
/// neutrals — it lays them out in the paragraph's direction — and the diagram
/// comes out backwards: the line renders as `rest 1:30 · 10–8 × 3`, and the
/// rep range now reads **10–8**, a descending range no plan contains. It is
/// not a translation gap; the same thing happens to `8–10` inside a perfectly
/// translated Arabic sentence, because direction is resolved per run and a run
/// of digits and dashes has no direction of its own to resolve to.
///
/// [ltr] gives it one. It wraps the run in `U+2066 LEFT-TO-RIGHT ISOLATE` and
/// `U+2069 POP DIRECTIONAL ISOLATE`, which tells the algorithm two things:
/// read the inside left-to-right, and treat the whole thing as one neutral
/// object from the outside. That second half is why an isolate is the right
/// tool and an *embedding* (`U+202A`/`U+202C`) is not — the isolate cannot
/// leak its direction into the Arabic on either side of it, so a spec can sit
/// inside a translated sentence without disturbing the sentence.
///
/// Use it for a composed technical spec, not for a word. A translated label
/// ("راحة", "مجموعات") is real text with a real direction and must be left
/// alone; it is the numeric skeleton around it that needs pinning.
library;

/// U+2066 LEFT-TO-RIGHT ISOLATE.
const String _lri = '\u2066';

/// U+2069 POP DIRECTIONAL ISOLATE.
const String _pdi = '\u2069';

/// [text], pinned to read left-to-right whatever the paragraph around it does.
///
/// Returns [text] unchanged when it is empty, so callers can pass a value that
/// may be blank without planting stray control characters in the layout.
String ltr(String text) => text.isEmpty ? text : '$_lri$text$_pdi';

/// [text] with any directional isolates stripped back out.
///
/// The isolate characters are invisible but they are still characters: they
/// survive `length`, `contains`, `==` and, most importantly, a `find.text` in
/// a widget test. Anything that compares a rendered string against a plain one
/// should compare against this.
String stripBidi(String text) =>
    text.replaceAll(_lri, '').replaceAll(_pdi, '');
