import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/coaching/evidence.dart';
import '../../domain/coaching/finding.dart';
import '../../domain/coaching/rules.dart';
import '../../domain/diet_state.dart';

/// **The coach's read on today, on the screen, without a model call.**
///
/// The findings shown here are the exact ones `coachingFindings` hands the AI
/// coach — same engine, same state, same at-most-three. That identity is the
/// point: what the user reads on the Diet screen and what the coach says in
/// chat cannot drift apart, because neither is deciding anything. It also
/// means the coaching survives offline, an empty AI budget and a rejected
/// reply — the sentences are already correct on their own.
///
/// And every one of them can be opened. Tapping **Why** resolves the finding's
/// `evidence` paths against the same state and lists what each field says, so
/// a recommendation is traceable to figures the user can check rather than
/// asserted by something they have to trust. A finding that could not answer
/// that question would have no business appearing here.
///
/// Renders nothing at all when there is nothing to say. Silence is a valid
/// output of the engine — a card that fills itself with filler when the rules
/// stayed quiet undoes the discipline that makes the loud cases mean anything.
class TodaysReadCard extends StatelessWidget {
  const TodaysReadCard({required this.state, this.localHour, super.key});

  final DietState state;

  /// The user's own hour of day, when known. Passed straight through: the
  /// engine's time-sensitive rules stay silent without it rather than guess.
  final int? localHour;

  @override
  Widget build(BuildContext context) {
    final findings = coachingFindings(state, localHour: localHour);
    if (findings.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const Key('todays-read'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Owns its leading gap, so a quiet day collapses to nothing at all
        // rather than to a doubled space where the card would have been.
        const SizedBox(height: 20),
        const TrainSectionLabel('Today’s read'),
        const SizedBox(height: 11),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final finding in findings)
                _FindingTile(
                  key: Key('finding-${finding.code}'),
                  finding: finding,
                  state: state,
                  showDivider: finding != findings.first,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One finding: its register, its sentence, and the figures behind it.
class _FindingTile extends StatefulWidget {
  const _FindingTile({
    required this.finding,
    required this.state,
    required this.showDivider,
    super.key,
  });

  final CoachingFinding finding;
  final DietState state;
  final bool showDivider;

  @override
  State<_FindingTile> createState() => _FindingTileState();
}

class _FindingTileState extends State<_FindingTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final finding = widget.finding;
    final evidence = evidenceFor(widget.state, finding.evidence);
    final color = _kindColor(finding.kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0x0FF4F4F0)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                findingKindLabel(finding.kind).toUpperCase(),
                style: TrainType.caption(size: 9, tracking: 0.18, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                finding.text,
                style: AppText.body.copyWith(
                  fontSize: 13.5,
                  height: 1.4,
                  color: TrainColors.inkPlain,
                ),
              ),
              // No evidence resolved means nothing honest to open, so the
              // affordance isn't offered — better than a Why that expands
              // into an empty box.
              if (evidence.isNotEmpty) ...[
                const SizedBox(height: 9),
                GestureDetector(
                  key: Key('finding-why-${finding.code}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = !_open),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _open ? 'HIDE' : 'WHY',
                        style: TrainType.caption(
                          size: 9,
                          tracking: 0.18,
                          color: TrainColors.ink2,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        _open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: TrainColors.ink3,
                      ),
                    ],
                  ),
                ),
                if (_open) ...[
                  const SizedBox(height: 8),
                  for (final value in evidence)
                    Padding(
                      key: Key('evidence-${finding.code}-${value.path}'),
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              value.label,
                              style: AppText.meta.copyWith(
                                color: TrainColors.ink3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              value.value,
                              textAlign: TextAlign.right,
                              style: TrainType.mono(
                                size: 11,
                                color: TrainColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The register's hue. Warning is the only one that raises its voice — the
/// clarifications are deliberately the quietest thing in the card, because
/// they qualify the others rather than competing with them.
Color _kindColor(FindingKind kind) => switch (kind) {
  FindingKind.warning => TrainColors.ember,
  FindingKind.recommendation => TrainColors.green,
  FindingKind.encouragement => TrainColors.green,
  FindingKind.observation => TrainColors.ink2,
  FindingKind.analysis => TrainColors.ink2,
  FindingKind.clarification => TrainColors.ink3,
};
