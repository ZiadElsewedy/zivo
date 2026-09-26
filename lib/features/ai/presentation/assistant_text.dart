import 'package:flutter/widgets.dart';

import '../../../core/util/bidi.dart';

/// How a reply from the coach is SHOWN — the display pass between the words
/// the model wrote (saved verbatim) and the paragraph on screen.
///
/// Three things the model's raw text gets wrong often enough to fix here, for
/// the live stream and the saved reply alike (the same function draws both,
/// so nothing jumps when one replaces the other):
///
///  * **Direction.** A reply takes the direction MOST of it is written in
///    ([dominantDirectionOf]), not its first letter — an Arabic reply that
///    opens with "Pull" is still an Arabic reply.
///  * **Mixed runs in Arabic.** Under right-to-left, each Latin/number run is
///    isolated ([isolateLtrRuns]) so `8–10` doesn't read `10–8` and
///    `Bench Press 3×8` stays one piece.
///  * **Stray Markdown.** The prompt asks for plain text
///    (`functions/ai/chat/prompt/sections/formatting.js`) and this screen
///    renders plain text, but a model still slips a `**bold**`, a `## heading`
///    or a `- ` bullet through. Those symbols would show up literally, so
///    they're stripped (bullets become the "• " the prompt asks for), and
///    runs of blank lines collapse to one — calm, even paragraph spacing.
///
/// Every rule is local to a line, so a half-streamed prefix formats the way
/// the finished text will — the live bubble never re-flows when the rest
/// arrives.
class AssistantDisplay {
  const AssistantDisplay(this.text, this.direction);

  /// What to paint.
  final String text;

  /// The paragraph's direction, decided from the whole text.
  final TextDirection direction;
}

final RegExp _heading = RegExp(r'^[ \t]*#{1,6}[ \t]+', multiLine: true);
final RegExp _mdBullet = RegExp(r'^([ \t]*)[-*+][ \t]+', multiLine: true);
final RegExp _trailingSpace = RegExp(r'[ \t]+$', multiLine: true);
final RegExp _extraBlankLines = RegExp(r'\n{3,}');

/// [raw] with stray Markdown syntax removed and paragraph spacing evened out.
/// Plain text passes through unchanged.
String cleanAssistantText(String raw) {
  var s = raw.replaceAll('\r\n', '\n');
  s = s.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
  s = s.replaceAll(_heading, '');
  s = s.replaceAllMapped(_mdBullet, (m) => '${m[1]}• ');
  s = s.replaceAll(_trailingSpace, '');
  s = s.replaceAll(_extraBlankLines, '\n\n');
  return s;
}

/// The display form of a reply. [directionSource] is the text to take the
/// direction from when [raw] is only part of it (the live bubble mid-stream,
/// so the paragraph doesn't flip as the words arrive); [fallback] is used
/// when the text has no direction of its own.
AssistantDisplay assistantDisplay(
  String raw, {
  required TextDirection fallback,
  String? directionSource,
}) {
  final cleaned = cleanAssistantText(raw);
  final direction = dominantDirectionOf(
    directionSource == null ? cleaned : cleanAssistantText(directionSource),
    fallback: fallback,
  );
  return AssistantDisplay(
    direction == TextDirection.rtl ? isolateLtrRuns(cleaned) : cleaned,
    direction,
  );
}
