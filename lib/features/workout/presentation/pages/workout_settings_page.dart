import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/deferred_write.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/workout_settings.dart';

/// The training settings screen — currently one knob, and a real one.
///
/// **Maximum session length** decides when a workout still showing as running
/// is one the user forgot to close. Three hours is a good default and a bad
/// constant: someone doing 40-minute sessions and someone doing a three-hour
/// strongman day do not share a threshold, and hard-coding either one would
/// make the protection wrong for the other.
///
/// The copy is careful about what the setting does NOT do, because that is the
/// part users are right to be suspicious of: nothing is capped to this number,
/// and no set, weight or completion is ever invented. A session past it is
/// ended at the last set the user actually logged.
class WorkoutSettingsPage extends StatelessWidget {
  const WorkoutSettingsPage({super.key});

  /// The choices offered. A slider would imply a precision this has no use
  /// for — the decision is "roughly how long do my workouts run", not a
  /// number of minutes.
  static const _options = <int>[60, 90, 120, 180, 240, 300, 360];

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).workoutSettings;
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: StreamBuilder<WorkoutSettings>(
        stream: repo?.watch() ?? const Stream.empty(),
        initialData: repo?.current ?? WorkoutSettings.defaults,
        builder: (context, snapshot) {
          final settings = snapshot.data ?? WorkoutSettings.defaults;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              22,
              12,
              22,
              TrainBottomInset.of(context),
            ),
            children: [
              TrainPageHeader(title: l(context).workoutSettings),
              const SizedBox(height: 22),
              TrainSectionLabel(l(context).workoutMaxSessionTitle),
              const SizedBox(height: 10),
              TrainListCard(
                rows: [
                  for (final minutes in _options)
                    TrainListRow(
                      icon: AppIcons.timer,
                      accent: TrainColors.green,
                      label: _label(context, minutes),
                      trailing: settings.maxSessionMinutes == minutes
                          ? Icon(
                              AppIcons.check,
                              size: 16,
                              color: TrainColors.green,
                            )
                          : null,
                      onTap: repo == null
                          ? null
                          : () => deferWrite(
                              repo.save(
                                settings.copyWith(maxSessionMinutes: minutes),
                              ),
                              failureMessage: l(
                                context,
                              ).workoutSettingsSaveFailed,
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                l(context).workoutMaxSessionBody,
                style: TrainType.ui(
                  size: 12.5,
                  color: TrainColors.ink3,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Reuses the app's existing duration keys (`workoutDurationH`/`Hm`) rather
  /// than minting a second pair that says the same thing.
  ///
  /// Deliberately NOT wrapped in `ltrFor`: in Arabic this is "3س 30د", which is
  /// Arabic letters around numbers, not a run of digits and neutrals. An RTL
  /// paragraph already lays it out right-to-left in the correct reading order,
  /// and pinning it LTR would reverse it. Every other `formatDurationShort`
  /// call site in the app leaves it alone for the same reason.
  String _label(BuildContext context, int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0
        ? l(context).workoutDurationH('$hours')
        : l(context).workoutDurationHm(hours, rest);
  }
}
