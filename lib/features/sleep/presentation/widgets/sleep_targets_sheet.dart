import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/async_action.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_targets.dart';
import '../sleep_labels.dart';

/// Bedtime, wake, and how long you want to sleep.
///
/// Duration is edited **independently** of the two clock times rather than
/// derived from them: wanting eight hours and wanting a fixed 23:00 bedtime
/// are two different intentions, and deriving one from the others would
/// silently overwrite whichever the user set second.
///
/// The sheet says outright that targets feed a reference line and nothing else.
/// ZIVO can tell you how long you slept; it cannot tell you whether the night
/// was good, so there is no score here and no streak.
Future<SleepTargets?> showSleepTargetsSheet(
  BuildContext context, {
  SleepTargets? initial,
}) {
  return showZivoSheet<SleepTargets>(
    context: context,
    isScrollControlled: false,
    builder: (_) => _SleepTargetsSheet(initial: initial),
  );
}

class _SleepTargetsSheet extends StatefulWidget {
  const _SleepTargetsSheet({this.initial});

  final SleepTargets? initial;

  @override
  State<_SleepTargetsSheet> createState() => _SleepTargetsSheetState();
}

class _SleepTargetsSheetState extends State<_SleepTargetsSheet>
    with AsyncAction {
  late SleepTargets _targets = widget.initial ?? SleepTargets.defaults;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    return ZivoSheetSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: ZivoSheetHandle()),
              const SizedBox(height: AppSpacing.base),
              Text(strings.sleepTargetsTitle, style: AppText.cardTitle),
              const SizedBox(height: AppSpacing.s),
              Text(
                strings.sleepTargetsHint,
                style: AppText.meta.copyWith(color: TrainColors.ink3),
              ),
              const SizedBox(height: AppSpacing.l),

              _TimeRow(
                label: strings.sleepTargetBedtime,
                minutes: _targets.bedtimeMinutes,
                onChanged: (m) =>
                    setState(() => _targets = _targets.copyWith(
                          bedtimeMinutes: m,
                        )),
              ),
              _TimeRow(
                label: strings.sleepTargetWake,
                minutes: _targets.wakeMinutes,
                onChanged: (m) =>
                    setState(() => _targets = _targets.copyWith(
                          wakeMinutes: m,
                        )),
              ),
              _DurationRow(
                label: strings.sleepTargetDuration,
                minutes: _targets.durationMinutes,
                onChanged: (m) =>
                    setState(() => _targets = _targets.copyWith(
                          durationMinutes: m,
                        )),
              ),

              const SizedBox(height: AppSpacing.l),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: TrainColors.sleepAccent,
                    foregroundColor: TrainColors.sleepOnAccent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  // `once: true` — this saves and pops, and a second tap
                  // across the await would run the whole handler again.
                  onPressed: () => runAction(
                    #save,
                    () async => Navigator.of(context).pop(_targets),
                    once: true,
                  ),
                  child: Text(strings.actionSave, style: AppText.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A clock target, adjusted in fifteen-minute steps.
///
/// Steps rather than a free picker because a target is a rough intention: an
/// interface that lets you set 22:47 implies a precision the goal does not
/// have, and then reports adherence against it.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _AdjustRow(
    label: label,
    value: ltrFor(context, formatMinutesSinceMidnight(context, minutes)),
    onDecrease: () => onChanged((minutes - 15) % (24 * 60)),
    onIncrease: () => onChanged((minutes + 15) % (24 * 60)),
  );
}

class _DurationRow extends StatelessWidget {
  const _DurationRow({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _AdjustRow(
    label: label,
    value: sleepDurationText(context, Duration(minutes: minutes)),
    // Clamped to a plausible range: a four-hour or fourteen-hour "target" is
    // a mis-tap, and adherence against one is noise.
    onDecrease: () => onChanged((minutes - 15).clamp(4 * 60, 12 * 60)),
    onIncrease: () => onChanged((minutes + 15).clamp(4 * 60, 12 * 60)),
  );
}

class _AdjustRow extends StatelessWidget {
  const _AdjustRow({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppText.rowTitle.copyWith(color: TrainColors.ink2),
          ),
        ),
        _Step(icon: Icons.remove, onTap: onDecrease, semanticLabel: label),
        SizedBox(
          width: 92,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: AppText.amount.copyWith(fontSize: 18),
          ),
        ),
        _Step(icon: Icons.add, onTap: onIncrease, semanticLabel: label),
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 18, color: TrainColors.sleepGlyph),
    tooltip: semanticLabel,
    visualDensity: VisualDensity.compact,
  );
}
