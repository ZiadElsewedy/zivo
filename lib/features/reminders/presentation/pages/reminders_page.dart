import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/deferred_write.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/notification_scheduler.dart';
import '../../domain/reminder.dart';
import '../../domain/reminders_repository.dart';
import '../reminder_labels.dart';
import '../widgets/edit_reminder_sheet.dart';

/// The reminders screen — one place to manage every local notification the user
/// schedules for themselves: meals, workouts, and anything else. Reached from
/// Settings.
///
/// A deliberately flat model (one [Reminder]: label + time + repeat + on/off)
/// covers all three cases (ADR-013). The stored list is the source of truth;
/// the OS's scheduled notifications are kept in sync by the app-root
/// subscription in `app.dart`, so this page only ever reads and writes the repo.
class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  RemindersRepository? _repo(BuildContext context) =>
      AppScope.of(context).reminders;

  /// Writes the new list, and — when it contains anything enabled — makes sure
  /// the OS permission has been asked for, surfacing a note if it was refused.
  Future<void> _persist(BuildContext context, List<Reminder> reminders) async {
    final repo = _repo(context);
    if (repo == null) return;

    if (reminders.any((r) => r.enabled)) {
      final scheduler = AppScope.of(context).notifications;
      if (scheduler != null) {
        final granted = await _ensurePermission(context, scheduler);
        if (!granted && context.mounted) {
          showZivoToast(context, l(context).remindersPermissionDenied);
        }
      }
    }

    if (!context.mounted) return;
    deferWrite(
      repo.save(reminders),
      failureMessage: l(context).remindersSaveFailed,
    );
  }

  Future<bool> _ensurePermission(
    BuildContext context,
    NotificationScheduler scheduler,
  ) => scheduler.requestPermission();

  void _add(BuildContext context, List<Reminder> current) {
    showEditReminderSheet(
      context,
      onSubmit: (reminder) => _persist(context, [...current, reminder]),
    );
  }

  void _edit(BuildContext context, List<Reminder> current, Reminder existing) {
    showEditReminderSheet(
      context,
      existing: existing,
      onSubmit: (updated) => _persist(context, [
        for (final r in current) if (r.id == updated.id) updated else r,
      ]),
      onDelete: () => _persist(context, [
        for (final r in current) if (r.id != existing.id) r,
      ]),
    );
  }

  void _toggle(
    BuildContext context,
    List<Reminder> current,
    Reminder reminder,
    bool enabled,
  ) {
    _persist(context, [
      for (final r in current)
        if (r.id == reminder.id) r.copyWith(enabled: enabled) else r,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo(context);
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: StreamBuilder<List<Reminder>>(
        stream: repo?.watch() ?? const Stream.empty(),
        initialData: repo?.current ?? const [],
        builder: (context, snapshot) {
          final reminders = snapshot.data ?? const [];
          return ListView(
            padding: EdgeInsets.fromLTRB(
              22,
              12,
              22,
              TrainBottomInset.of(context),
            ),
            children: [
              TrainPageHeader(
                title: l(context).remindersTitle,
                action: repo == null
                    ? null
                    : TrainHeaderAction(
                        icon: AppIcons.add,
                        accent: TrainColors.neutralMark,
                        semanticLabel: l(context).remindersAdd,
                        onTap: () => _add(context, reminders),
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                l(context).remindersIntro,
                style: TrainType.ui(
                  size: 12.5,
                  color: TrainColors.ink3,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              if (reminders.isEmpty)
                _EmptyState(onAdd: repo == null ? null : () => _add(context, reminders))
              else
                TrainListCard(
                  rows: [
                    for (final reminder in reminders)
                      _ReminderRow(
                        reminder: reminder,
                        onTap: () => _edit(context, reminders, reminder),
                        onToggle: (value) =>
                            _toggle(context, reminders, reminder, value),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One reminder as a row: kind icon · name over "time · repeat" · an on/off
/// switch. Tapping the row (anywhere but the switch) opens the edit sheet.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.onTap,
    required this.onToggle,
  });

  final Reminder reminder;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    // The time is a composed clock run and is pinned LTR; the repeat summary
    // beside it holds translated weekday words, so it is left to lay itself out.
    final meta =
        '${ltrFor(context, reminderTimeLabel(context, reminder))}  ·  '
        '${reminderRepeatSummary(context, reminder)}';
    final syncSummary = reminderSyncSummary(context, reminder);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
          child: Row(
            children: [
              TrainIconTile(
                icon: reminderKindIcon(reminder.kind),
                accent: reminder.enabled
                    ? TrainColors.neutralMark
                    : TrainColors.inkAt(0.35),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminderDisplayLabel(context, reminder),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.ui(
                        size: 15,
                        weight: FontWeight.w700,
                        color: reminder.enabled
                            ? TrainColors.inkPlain
                            : TrainColors.ink3,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.meta.copyWith(color: TrainColors.ink3),
                    ),
                    if (syncSummary != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            AppIcons.reminderSync,
                            size: 12,
                            color: reminder.enabled
                                ? TrainColors.neutralMark
                                : TrainColors.inkAt(0.35),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              isolate(syncSummary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.meta.copyWith(
                                color: reminder.enabled
                                    ? TrainColors.inkAt(0.6)
                                    : TrainColors.ink3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: reminder.enabled,
                onChanged: onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: TrainColors.sectionFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        children: [
          Icon(AppIcons.reminders, size: 30, color: TrainColors.inkAt(0.4)),
          const SizedBox(height: 14),
          Text(
            l(context).remindersEmpty,
            style: AppText.cardTitle.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            l(context).remindersEmptyBody,
            textAlign: TextAlign.center,
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onAdd,
              icon: Icon(AppIcons.add, size: 18, color: TrainColors.inkPlain),
              label: Text(
                l(context).remindersAdd,
                style: AppText.button.copyWith(color: TrainColors.inkPlain),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
