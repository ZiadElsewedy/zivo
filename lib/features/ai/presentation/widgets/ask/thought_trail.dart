import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_turn_event.dart';
import '../../ai_labels.dart';
import '../../ai_thought.dart';
import '../../ask_constants.dart';

/// What ZIVO is doing right now, while a turn works — the head of the trail.
class LiveThought {
  const LiveThought({
    required this.kind,
    required this.label,
    this.slow = false,
  });

  final AiThoughtKind kind;

  /// "Reading your meal plan…" — already localized.
  final String label;

  /// The turn has gone quiet — add the honest "still working" line.
  final bool slow;
}

/// ZIVO's thought process for one reply, simplified: the kinds of work it did
/// ("Read your meal plan", "Suggested alternatives") and, while the turn
/// works, the one thing it is doing now — never a tool's name, input or
/// result.
///
/// Two shapes, one widget, so nothing jumps between them:
///
/// * **Working** ([live] set): each finished step as a quiet line on a thin
///   trail, and the live line at its head — a breathing dot and a slow sheen
///   across the words, in the tone of the work (mist for reading, heather for
///   analysing, brass for numbers, rosewater for suggestions…). This is the
///   one animated moment on the screen; everything around it stays still.
/// * **Settled** ([live] null — ZIVO has started writing, or the reply is
///   saved): the steps fold into one line of past-tense verbs, each behind a
///   dot of its tone ("● Read  ● Suggested"). Tapping it unfolds the steps.
///
/// In debug builds the unfolded steps also show each raw tool id
/// ([kShowAiToolIds]) so the chat can be tuned against what really ran; a
/// release build never shows one. A model fallback is always shown — the user
/// should see that ZIVO carried on by itself instead of failing.
class ThoughtTrail extends StatefulWidget {
  const ThoughtTrail({required this.steps, this.live, super.key});

  final List<AiActivityStep> steps;
  final LiveThought? live;

  @override
  State<ThoughtTrail> createState() => _ThoughtTrailState();
}

class _ThoughtTrailState extends State<ThoughtTrail> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final still = MediaQuery.of(context).disableAnimations;
    final live = widget.live;

    // Finished lookups this build can name. A running one is the live line's
    // job; an unknown one is left out rather than shown as an identifier.
    final done = [
      for (final step in widget.steps)
        if (!step.isFallback &&
            step.status != AiStepStatus.running &&
            aiThoughtKnowsTool(step.tool))
          step,
    ];
    final fallbacks = [
      for (final step in widget.steps)
        if (step.isFallback) step,
    ];

    final Widget body;
    if (live != null) {
      body = _TrailColumn(
        key: const ValueKey('working'),
        rows: [
          for (final step in done) _DoneRow(step: step),
          _LiveRow(thought: live),
        ],
      );
    } else if (done.isEmpty) {
      body = const SizedBox(key: ValueKey('empty'), width: double.infinity);
    } else if (_expanded) {
      body = _TrailColumn(
        key: const ValueKey('expanded'),
        onTap: () => setState(() => _expanded = false),
        semanticsHint: s.askThoughtHideSteps,
        rows: [for (final step in done) _DoneRow(step: step)],
      );
    } else {
      body = _Summary(
        key: const ValueKey('summary'),
        steps: done,
        onTap: () => setState(() => _expanded = true),
      );
    }

    final hasContent = live != null || done.isNotEmpty || fallbacks.isNotEmpty;
    return _EaseSize(
      still: still,
      duration: const Duration(milliseconds: 280),
      child: !hasContent
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in fallbacks) ..._fallbackRows(context, f),
                  AnimatedSwitcher(
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.topStart,
                      children: [...previous, ?current],
                    ),
                    child: body,
                  ),
                ],
              ),
            ),
    );
  }

  /// "⚠ Gemini Flash unavailable" then "↳ Switched to Claude Sonnet". The
  /// technical reason stays in usage telemetry.
  List<Widget> _fallbackRows(BuildContext context, AiActivityStep step) {
    final s = l(context);
    return [
      _NoteRow(
        icon: AppIcons.warning,
        label: s.askFallbackUnavailable(
          aiModelSelectionText(context, step.fallbackFrom!),
        ),
      ),
      const SizedBox(height: 4),
      _NoteRow(
        icon: AppIcons.modelSwitched,
        label: s.askFallbackSwitched(
          aiModelSelectionText(context, step.fallbackTo!),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}

/// The dot column every row shares, so the rows hang off one thin trail.
const double _kGutter = 14;
const double _kGap = 8;

/// Rows threaded on a hairline drawn through their dots.
class _TrailColumn extends StatelessWidget {
  const _TrailColumn({
    required this.rows,
    this.onTap,
    this.semanticsHint,
    super.key,
  });

  final List<Widget> rows;
  final VoidCallback? onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final column = Stack(
      children: [
        if (rows.length > 1)
          PositionedDirectional(
            start: _kGutter / 2 - 0.5,
            top: 9,
            bottom: 9,
            child: Container(width: 1, color: TrainColors.hairlineStrong),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              rows[i],
            ],
          ],
        ),
      ],
    );
    if (onTap == null) return column;
    return Semantics(
      button: true,
      hint: semanticsHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: column,
      ),
    );
  }
}

/// A finished step: a small dot in its tone, then what ZIVO did.
class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.step});

  final AiActivityStep step;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final failed = step.status == AiStepStatus.error;
    final label = aiThoughtDoneLabel(s, step.tool)!;
    final tint = aiThoughtTint(aiThoughtKindForTool(step.tool));
    return Semantics(
      label: failed ? '$label, ${s.askActivityFailed}' : label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _kGutter,
            height: 18,
            child: Center(
              child: failed
                  ? Icon(AppIcons.warning, size: 12, color: TrainColors.ink3)
                  : _Dot(color: tint, size: 5),
            ),
          ),
          const SizedBox(width: _kGap),
          Flexible(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (kShowAiToolIds)
                    TextSpan(
                      text: '  ${step.tool}',
                      style: TrainType.mono(size: 10, color: TrainColors.ink4),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrainType.ui(
                size: 12.5,
                weight: FontWeight.w500,
                color: failed ? TrainColors.ink4 : TrainColors.ink3,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The head of a working trail: a dot that breathes and a slow sheen across
/// the words, both in the tone of the work.
class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.thought});

  final LiveThought thought;

  @override
  Widget build(BuildContext context) {
    final tint = aiThoughtTint(thought.kind);
    final style = TrainType.ui(
      size: 13.5,
      weight: FontWeight.w600,
      color: tint,
      height: 1.3,
    );
    return Semantics(
      liveRegion: true,
      label: thought.label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: _kGutter,
                height: 18,
                child: Center(child: _Pulse(color: tint)),
              ),
              const SizedBox(width: _kGap),
              Flexible(
                child: AnimatedSwitcher(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  child: _Sheen(
                    key: ValueKey(thought.label),
                    color: tint,
                    child: Text(
                      thought.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ),
              ),
            ],
          ),
          _EaseSize(
            still: MediaQuery.of(context).disableAnimations,
            duration: const Duration(milliseconds: 240),
            child: thought.slow
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: _kGutter + _kGap,
                      top: 3,
                    ),
                    child: Text(
                      l(context).askStillWorking,
                      style: TrainType.ui(
                        size: 12,
                        weight: FontWeight.w500,
                        color: TrainColors.ink3,
                      ),
                    ),
                  )
                : const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }
}

/// The settled trail: one line of past-tense verbs, each behind a dot of its
/// tone, in the order ZIVO did them. A kind done twice is named once.
class _Summary extends StatelessWidget {
  const _Summary({required this.steps, required this.onTap, super.key});

  final List<AiActivityStep> steps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = l(context);
    final kinds = <AiThoughtKind>[];
    for (final step in steps) {
      final kind = aiThoughtKindForTool(step.tool);
      if (!kinds.contains(kind) && aiThoughtVerb(s, kind) != null) {
        kinds.add(kind);
      }
    }
    if (kinds.isEmpty) return const SizedBox(width: double.infinity);
    final verbs = [for (final k in kinds) aiThoughtVerb(s, k)!];
    final style = TrainType.ui(
      size: 12.5,
      weight: FontWeight.w500,
      color: TrainColors.ink3,
      height: 1.3,
    );
    return Semantics(
      button: true,
      label: verbs.join(', '),
      hint: s.askThoughtShowSteps,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // A comfortable target for a one-line control.
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < kinds.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                SizedBox(
                  width: i == 0 ? _kGutter : 7,
                  child: Align(
                    alignment: i == 0
                        ? Alignment.center
                        : AlignmentDirectional.centerStart,
                    child: _Dot(color: aiThoughtTint(kinds[i]), size: 5),
                  ),
                ),
                SizedBox(width: i == 0 ? _kGap : 2),
                Text(verbs[i], style: style),
              ],
              const SizedBox(width: 6),
              Icon(AppIcons.chevronDown, size: 12, color: TrainColors.ink4),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain note in the trail — the fallback rows.
class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _kGutter,
            child: Icon(icon, size: 12, color: TrainColors.ink3),
          ),
          const SizedBox(width: _kGap),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TrainType.ui(
                size: 12.5,
                weight: FontWeight.w500,
                color: TrainColors.ink3,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A dot with a soft ring breathing out of it — "alive", without a spinner.
/// Mounted only while a turn works, so its loop never outlives the turn.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});

  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return _Dot(color: widget.color, size: 6);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 6 + 8 * t,
                height: 6 + 8 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - t)),
                ),
              ),
              _Dot(color: widget.color, size: 6),
            ],
          ),
        );
      },
    );
  }
}

/// A band of light that drifts across [child] — the live line's sheen. The
/// words stay fully legible at every point of the sweep: the band only lifts
/// the tone toward the page's ink, it never fades the text out.
class _Sheen extends StatefulWidget {
  const _Sheen({required this.color, required this.child, super.key});

  final Color color;
  final Widget child;

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    final base = widget.color;
    final lit = Color.lerp(base, TrainColors.ink, 0.55)!;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // The band travels from well before the text to well past it, so
        // the sweep enters and leaves rather than popping at the edges.
        final x = -1.0 + 3.0 * _c.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: [base, lit, base],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(x - 1, 0),
            end: Alignment(x + 1, 0),
            tileMode: TileMode.clamp,
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Eases its child's size changes — or, under reduce motion, just lays the
/// child out (an [AnimatedSize] with a zero duration re-dirties itself
/// mid-layout).
class _EaseSize extends StatelessWidget {
  const _EaseSize({
    required this.still,
    required this.duration,
    required this.child,
  });

  final bool still;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => still
      ? child
      : AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topStart,
          child: child,
        );
}
