import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../domain/ai_message.dart';
import '../../../domain/ai_role.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble(
    this.message, {
    this.animate = false,
    this.onRevealDone,
    this.streaming = false,
    super.key,
  });

  final AiMessage message;

  /// When true, the (assistant) text types in rather than appearing at once.
  final bool animate;

  /// Called once the typewriter reveal finishes — the page drops the
  /// message's reveal flag so later rebuilds render it statically.
  final VoidCallback? onRevealDone;

  /// When true (the provisional live bubble mid-turn), a soft iris caret
  /// rides the text so "still writing" is visible at a glance.
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiRole.user;
    // ZIVO's replies read a touch larger than the user's own lines — it's the
    // long-form text the user actually reads, so a bump to 16 (from body's
    // 14.5) with generous leading makes it easier on the eyes without
    // ballooning the compact user pills.
    final style = isUser
        ? TrainType.ui(
            size: 13.5,
            weight: FontWeight.w600,
            color: TrainColors.inkPlain,
            height: 1.4,
          )
        : TrainType.ui(
            size: 15,
            weight: FontWeight.w400,
            color: TrainColors.ink,
            height: 1.55,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isUser ? 16 : 2,
                vertical: isUser ? 12 : 2,
              ),
              constraints: BoxConstraints(
                // The handoff caps a user bubble at 74% so a long question
                // still reads as a quoted aside, not a paragraph.
                maxWidth: isUser
                    ? MediaQuery.of(context).size.width * 0.74
                    : double.infinity,
              ),
              decoration: isUser
                  // Glass, not a saturated fill: violet is the assistant's
                  // chrome here, and painting the USER's own words in it
                  // spends the hue on the wrong speaker. The softened
                  // bottom-right tail still points the pill at its author.
                  ? const BoxDecoration(
                      color: Color(0x12FFFFFF),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(6),
                      ),
                    )
                  : null,
              child: animate
                  ? TypewriterText(
                      message.content,
                      style: style,
                      onDone: onRevealDone,
                    )
                  : streaming && !MediaQuery.of(context).disableAnimations
                  ? Text.rich(
                      TextSpan(
                        text: message.content,
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: StreamCaret(),
                          ),
                        ],
                      ),
                      style: style,
                    )
                  : Text(message.content, style: style),
            ),
          ),
        ],
      ),
    );
  }
}

/// The caret riding the end of a streaming reply — a softly breathing iris
/// bar. Only mounted mid-turn, so its loop never outlives the stream.
class StreamCaret extends StatefulWidget {
  const StreamCaret({super.key});

  @override
  State<StreamCaret> createState() => _StreamCaretState();
}

class _StreamCaretState extends State<StreamCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    lowerBound: 0.25,
    upperBound: 1,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 2.5,
        height: 14,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: TrainColors.violetGlyph,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Reveals [text] left-to-right on mount, like the assistant is composing it.
/// One-shot (never repeats), so `pumpAndSettle` completes it; honors the
/// platform "reduce motion" setting by showing the full text immediately.
/// [onDone] fires when the reveal completes (including instantly under
/// reduce-motion) — the caller uses it to retire its "revealing" flag.
class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    required this.style,
    this.onDone,
    super.key,
  });

  final String text;
  final TextStyle style;
  final VoidCallback? onDone;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // ~20ms/char with a hard cap — a calm, natural write (matching the
    // streamed path's slower cadence) that still never crawls on long replies.
    // This is only the fallback for turns that arrived without deltas.
    final ms = math.min(widget.text.characters.length * 20, 3200);
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: math.max(ms, 1)),
    )..forward().whenComplete(() => widget.onDone?.call());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      // Full text immediately; retire the caller's reveal flag post-frame
      // (a synchronous callback here would setState during build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      });
      return Text(widget.text, style: widget.style);
    }
    final chars = widget.text.characters;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final shown = (chars.length * _c.value).round();
        return Text(chars.take(shown).toString(), style: widget.style);
      },
    );
  }
}
