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

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// U+2066 LEFT-TO-RIGHT ISOLATE.
const String _lri = '\u2066';

/// U+2068 FIRST STRONG ISOLATE.
const String _fsi = '\u2068';

/// U+2069 POP DIRECTIONAL ISOLATE.
const String _pdi = '\u2069';

/// [text], pinned to read left-to-right whatever the paragraph around it does.
///
/// Returns [text] unchanged when it is empty, so callers can pass a value that
/// may be blank without planting stray control characters in the layout.
String ltr(String text) => text.isEmpty ? text : '$_lri$text$_pdi';

/// [text] isolated from the sentence around it, with its direction decided by
/// its own first strong character (`U+2068 FIRST STRONG ISOLATE`).
///
/// This is the one to use for **text you did not write** — a plan name, an
/// exercise name, a track title, anything typed by the user or imported from
/// their PDF. [ltr] would be a guess: a plan called "Push · Pull" is
/// left-to-right, one called "دفع · سحب" is not, and forcing either is wrong
/// half the time. FSI asks the string. What it guarantees either way is the
/// part that matters — that the name is one indivisible object inside the
/// sentence, so an Arabic caption reading "{plan} · {n} exercises" cannot come
/// apart with the count stranded at the far end of the line.
///
/// Applied unconditionally, unlike [ltrFor]: a name of unknown direction is
/// just as capable of fragmenting an *English* sentence as an Arabic one.
String isolate(String text) => text.isEmpty ? text : '$_fsi$text$_pdi';

/// [text], pinned left-to-right **only where that actually does something** —
/// that is, when the paragraph around [context] runs right-to-left.
///
/// Inside an LTR paragraph an LTR isolate changes nothing on screen: the run
/// was already going to be laid out left-to-right. What it does change is the
/// *string*, and invisibly — the isolate characters survive `==`,
/// `contains` and `find.textContaining`, so an unconditional wrap silently
/// splits `rest 3:00` into `rest <LRI>3:00<PDI>` for every English caller and every
/// English test that ever reads one of these lines back. Gating on direction
/// keeps English byte-for-byte what it was and confines the control
/// characters to the language that needs them.
///
/// Prefer this over [ltr] anywhere a [BuildContext] is in hand.
String ltrFor(BuildContext context, String text) =>
    Directionality.of(context) == TextDirection.rtl ? ltr(text) : text;

/// [text] with any directional isolates stripped back out.
///
/// The isolate characters are invisible but they are still characters: they
/// survive `length`, `contains`, `==` and, most importantly, a `find.text` in
/// a widget test. Anything that compares a rendered string against a plain one
/// should compare against this.
String stripBidi(String text) => text
    .replaceAll(_lri, '')
    .replaceAll(_fsi, '')
    .replaceAll(_pdi, '');

/// The direction [text] would choose for itself — the direction of its first
/// strong character, or [fallback] when it has none (digits, punctuation and
/// emoji are not strong, and a string of nothing else has no opinion).
///
/// [isolate] is the *inline* version of this idea: it hands one run its own
/// direction and lets the sentence around it keep the paragraph's. This is the
/// **paragraph** version, for a string that is not inside a sentence but *is*
/// the whole block — a chat message, a track title on its own line.
///
/// There, direction decides more than word order. It decides which edge the
/// text hangs off, where a trailing full stop lands, and which end
/// `TextOverflow.ellipsis` eats. Left to the UI's locale, an English reply in
/// an Arabic app comes out right-aligned with its final `.` flung to the far
/// side of the last line, and a Latin track title truncates as
/// `…Fixture Track Th` — the ellipsis chewing the end it is standing at the
/// wrong side of. Neither is a translation gap: the words are fine and the
/// paragraph simply took the app's direction instead of the text's.
///
/// Pass the surrounding [Directionality] as [fallback] so a directionless
/// string keeps behaving exactly as it does today.
TextDirection directionOf(String text, {required TextDirection fallback}) {
  if (Bidi.startsWithRtl(text)) return TextDirection.rtl;
  if (Bidi.startsWithLtr(text)) return TextDirection.ltr;
  return fallback;
}

/// [directionOf] with the ambient [Directionality] as the fallback.
TextDirection directionOfFor(BuildContext context, String text) =>
    directionOf(text, fallback: Directionality.of(context));
