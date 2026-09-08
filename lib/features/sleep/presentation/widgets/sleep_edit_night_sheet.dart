import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/async_action.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_night.dart';
import '../sleep_labels.dart';

/// The result of a manual correction: two UTC instants.
class SleepNightEdit {
  const SleepNightEdit({required this.startAtUtc, required this.endAtUtc});

  final DateTime startAtUtc;
  final DateTime endAtUtc;
}

/// Correcting a night by hand.
///
/// The sheet states plainly that the correction is stored **as the user's
/// own** and that the measured times are kept. Both halves matter: the first
/// is why the night's badge changes to "Logged by you" afterwards — a
/// surprise otherwise — and the second is the promise the resolver actually
/// keeps, since an override moves the measurement into the night's alternates
/// rather than deleting it (`docs/SLEEP_SYSTEM.md` §12.4).
Future<SleepNightEdit?> showSleepEditNightSheet(
  BuildContext context,
  SleepNight night,
) {
  return showZivoSheet<SleepNightEdit>(
    context: context,
    isScrollControlled: false,
    builder: (_) => _SleepEditNightSheet(night: night),
  );
}

class _SleepEditNightSheet extends StatefulWidget {
  const _SleepEditNightSheet({required this.night});

  final SleepNight night;

  @override
  State<_SleepEditNightSheet> createState() => _SleepEditNightSheetState();
}

class _SleepEditNightSheetState extends State<_SleepEditNightSheet>
    with AsyncAction {
  late DateTime _start;
  late DateTime _end;
  late final int _offsetMinutes;

  @override
  void initState() {
    super.initState();
    final main = widget.night.main;
    _offsetMinutes =
        main?.startOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes;
    // Seeded from the existing night where there is one, so a correction is a
    // nudge rather than a re-entry. With nothing to seed from, the default is
    // an ordinary night ending on this sleep-day.
    final day = widget.night.sleepDay;
    _start = main?.localStart ??
        DateTime(day.year, day.month, day.day).subtract(
          const Duration(hours: 1),
        );
    _end = main?.localEnd ?? DateTime(day.year, day.month, day.day, 7);
  }

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final valid = _end.isAfter(_start);

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
              Text(strings.sleepEditNight, style: AppText.cardTitle),
              const SizedBox(height: AppSpacing.s),
              Text(
                strings.sleepEditHint,
                style: AppText.meta.copyWith(color: TrainColors.ink3),
              ),
              const SizedBox(height: AppSpacing.l),

              _PickRow(
                label: strings.sleepDurationLabel,
                value: ltrFor(context, formatClockTime(context, _start)),
                onTap: () => _pick(isStart: true),
              ),
              _PickRow(
                label: strings.sleepTargetWake,
                value: ltrFor(context, formatClockTime(context, _end)),
                onTap: () => _pick(isStart: false),
              ),

              const SizedBox(height: AppSpacing.m),
              Text(
                valid
                    ? sleepDurationText(context, _end.difference(_start))
                    : strings.sleepNoData,
                style: AppText.amount.copyWith(
                  fontSize: 22,
                  color: valid ? TrainColors.ink : TrainColors.ink4,
                ),
              ),

              const SizedBox(height: AppSpacing.l),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: TrainColors.sleepAccent,
                    foregroundColor: TrainColors.sleepOnAccent,
                    disabledBackgroundColor: TrainColors.glassStrong,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  onPressed: !valid
                      ? null
                      : () => runAction(#save, () async {
                          Navigator.of(context).pop(
                            SleepNightEdit(
                              // Back to instants: the wall-clock times the
                              // user picked are read in the offset the night
                              // was lived in, not in wherever the phone is now.
                              startAtUtc: _start.subtract(
                                Duration(minutes: _offsetMinutes),
                              ),
                              endAtUtc: _end.subtract(
                                Duration(minutes: _offsetMinutes),
                              ),
                            ),
                          );
                        }, once: true),
                  child: Text(strings.actionSave, style: AppText.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final updated = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (isStart) {
        _start = updated;
        // A bedtime picked after the wake time means the user meant the
        // evening before — the ordinary case, since most nights cross
        // midnight. Shifting the date rather than rejecting the input is what
        // makes "23:15" work without asking which day it belongs to.
        if (!_end.isAfter(_start)) {
          _start = _start.subtract(const Duration(days: 1));
        }
      } else {
        _end = updated;
        if (!_end.isAfter(_start)) {
          _end = _end.add(const Duration(days: 1));
        }
      }
    });
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.field),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppText.rowTitle.copyWith(color: TrainColors.ink2),
          ),
          Text(
            value,
            style: AppText.amount.copyWith(
              fontSize: 18,
              color: TrainColors.sleepGlyph,
            ),
          ),
        ],
      ),
    ),
  );
}
