import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/calendar.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/util/deferred_write.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/live_session.dart';
import '../../domain/training_day_mark.dart';
import '../../domain/training_day_mark_repository.dart';
import '../../domain/training_streak.dart';
import '../workout_labels.dart';

/// The sheet behind a rest day on the streak drill-down: say why you didn't
/// train, and — where the rules allow it — spend a restore.
///
/// The two are presented as what they are, and the copy is doing real work
/// here. A reason is context and says so ("it never changes your streak"); a
/// restore is the one thing that touches the number, and its confirmation
/// states plainly that it bridges a gap and does not add a workout. A user who
/// believes writing "travel" repaired their streak would be wrong about their
/// own history, which is the failure this whole feature exists to avoid.
Future<void> showMissedDaySheet(
  BuildContext context, {
  required DateTime day,
  required DateTime now,
  required List<LiveSession> sessions,
  required List<TrainingDayMark> marks,
  required TrainingDayMarkRepository repository,
}) {
  final key = startOfDay(day);
  final existing = marks.where((m) => startOfDay(m.day) == key).firstOrNull;
  final canRestore = canRestoreDay(
    day: key,
    now: now,
    sessions: sessions,
    marks: marks,
  );

  return showZivoSheet<void>(
    context: context,
    builder: (sheetContext) => ZivoSheetSurface(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ZivoSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatWeekdayDate(sheetContext, key),
                    style: TrainType.ui(
                      size: 19,
                      weight: FontWeight.w700,
                      color: TrainColors.inkPlain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l(sheetContext).workoutStreakWhyMissed,
                    style: TrainType.ui(size: 13, color: TrainColors.ink3),
                  ),
                ],
              ),
            ),
            TrainListCard(
              rows: [
                for (final reason in MissedDayReason.values)
                  TrainListRow(
                    icon: _reasonIcon(reason),
                    accent: TrainColors.green,
                    label: missedDayReasonLabel(sheetContext, reason),
                    trailing: existing?.reason == reason
                        ? Icon(
                            AppIcons.check,
                            size: 16,
                            color: TrainColors.green,
                          )
                        : null,
                    onTap: () {
                      final next = (existing ?? _blank(key, now)).copyWith(
                        // Tapping the reason already set clears it — the same
                        // affordance both ways, no separate "remove".
                        reason: existing?.reason == reason ? null : reason,
                      );
                      final failure = l(sheetContext).trainingDayMarkSaveFailed;
                      Navigator.of(sheetContext).pop();
                      deferWrite(
                        next.isEmpty
                            ? repository.deleteMark(key)
                            : repository.saveMark(next),
                        failureMessage: failure,
                      );
                    },
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Text(
                l(sheetContext).workoutStreakReasonSaved,
                style: TrainType.ui(size: 11.5, color: TrainColors.ink4),
              ),
            ),
            const SizedBox(height: 18),
            // The restore, kept visually apart from the reasons above — it is
            // the only control on this sheet that changes a number.
            TrainListCard(
              rows: [
                TrainListRow(
                  icon: AppIcons.streak,
                  accent: canRestore || (existing?.restored ?? false)
                      ? TrainColors.ember
                      : TrainColors.ink4,
                  label: l(sheetContext).workoutStreakRestore,
                  value: (existing?.restored ?? false)
                      ? l(sheetContext).workoutStreakRestored
                      : (canRestore
                            ? null
                            : l(
                                sheetContext,
                              ).workoutStreakRestoreUnavailable(
                                kRestoreCooldownDays,
                              )),
                  onTap: canRestore
                      ? () async {
                          final confirmed = await confirmDestructive(
                            sheetContext,
                            title: l(sheetContext).workoutStreakRestoreTitle,
                            body: l(sheetContext).workoutStreakRestoreBody,
                            confirmLabel: l(sheetContext).workoutStreakRestore,
                          );
                          if (!confirmed || !sheetContext.mounted) return;
                          final mark = (existing ?? _blank(key, now)).copyWith(
                            restored: true,
                          );
                          final failure =
                              l(sheetContext).trainingDayMarkSaveFailed;
                          Navigator.of(sheetContext).pop();
                          deferWrite(
                            repository.saveMark(mark),
                            failureMessage: failure,
                          );
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 22),
          ],
        ),
      ),
    ),
  );
}

TrainingDayMark _blank(DateTime day, DateTime now) =>
    TrainingDayMark(day: day, createdAt: now);

IconData _reasonIcon(MissedDayReason reason) => switch (reason) {
  MissedDayReason.rest => AppIcons.sleep,
  MissedDayReason.recovery => AppIcons.sessions,
  MissedDayReason.travel => AppIcons.catTravel,
  MissedDayReason.illness => AppIcons.warning,
  MissedDayReason.busy => AppIcons.calendarClock,
  MissedDayReason.other => AppIcons.schedule3Day,
};
