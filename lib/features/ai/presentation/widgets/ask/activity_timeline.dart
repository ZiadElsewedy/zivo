import 'package:flutter/material.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_turn_event.dart';
import '../../ai_labels.dart';
import 'thinking_rail.dart';

/// What the agent actually did for a reply — one chip per read tool it ran
/// ("✓ Grab · Diet details"), in order, above the reply.
///
/// Built from the loop's real events (live) or the reply's persisted
/// `activity` (history), never from the model's reasoning, and never showing
/// a tool's input, result or identifier: an unknown tool is left out rather
/// than named. Violet, because it is system/meta chrome — the same hue as the
/// thinking rail it sits above.
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline(this.steps, {super.key});

  final List<AiActivityStep> steps;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final step in steps) {
      final label = aiActivityLabel(context, step.tool);
      if (label == null) continue;
      rows.add(_ActivityRow(label: label, status: step.status));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 5),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.label, required this.status});

  final String label;
  final AiStepStatus status;

  @override
  Widget build(BuildContext context) {
    final failed = status == AiStepStatus.error;
    final ink = failed ? TrainColors.ink3 : TrainColors.violetGlyph;
    final Widget glyph = switch (status) {
      AiStepStatus.running => const SizedBox(
        width: 14,
        height: 14,
        child: Center(child: GlowOrb(opacity: 0.9)),
      ),
      AiStepStatus.ok => Icon(AppIcons.check, size: 14, color: ink),
      AiStepStatus.error => Icon(AppIcons.warning, size: 14, color: ink),
    };
    return Semantics(
      label: failed ? '$label, ${l(context).askActivityFailed}' : label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyph,
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: failed ? TrainColors.hairline : TrainColors.violetWash,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrainType.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  color: ink,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
