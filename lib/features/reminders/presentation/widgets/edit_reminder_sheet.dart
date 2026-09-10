import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/reminder.dart';
import '../reminder_labels.dart';

/// Opens the create/edit sheet for a reminder.
///
/// [existing] is null when creating. [onSubmit] receives the built reminder;
/// [onDelete] (create → null) removes the one being edited. The sheet closes
/// itself before either fires — the page owns the list and the durable save.
Future<void> showEditReminderSheet(
  BuildContext context, {
  Reminder? existing,
  required ValueChanged<Reminder> onSubmit,
  VoidCallback? onDelete,
}) {
  return showZivoSheet<void>(
    context: context,
    builder: (_) => _EditReminderSheet(
      existing: existing,
      onSubmit: onSubmit,
      onDelete: onDelete,
    ),
  );
}

class _EditReminderSheet extends StatefulWidget {
  const _EditReminderSheet({
    required this.existing,
    required this.onSubmit,
    required this.onDelete,
  });

  final Reminder? existing;
  final ValueChanged<Reminder> onSubmit;
  final VoidCallback? onDelete;

  @override
  State<_EditReminderSheet> createState() => _EditReminderSheetState();
}

class _EditReminderSheetState extends State<_EditReminderSheet> {
  late final TextEditingController _label;
  late ReminderKind _kind;
  late TimeOfDay _time;
  late Set<int> _weekdays;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _label = TextEditingController(text: r?.label ?? '');
    _kind = r?.kind ?? ReminderKind.meal;
    _time = r == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : TimeOfDay(hour: r.hour, minute: r.minute);
    _weekdays = {...?r?.weekdays};
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _isEveryDay => _weekdays.isEmpty || _weekdays.length == 7;

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  void _toggleDay(int weekday) {
    setState(() {
      if (_weekdays.contains(weekday)) {
        _weekdays.remove(weekday);
      } else {
        _weekdays.add(weekday);
      }
    });
  }

  void _save() {
    final reminder = Reminder.clamped(
      id: widget.existing?.id ?? _newId(),
      label: _label.text,
      kind: _kind,
      hour: _time.hour,
      minute: _time.minute,
      // An all-seven selection is stored as "every day" (empty) — the two mean
      // the same thing and the empty form schedules one alarm instead of seven.
      weekdays: _isEveryDay ? const {} : _weekdays,
      enabled: widget.existing?.enabled ?? true,
    );
    Navigator.of(context).pop();
    widget.onSubmit(reminder);
  }

  Future<void> _delete() async {
    final confirmed = await confirmDestructive(
      context,
      title: l(context).remindersDelete,
      body: l(context).remindersDeleteConfirm,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
    widget.onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final accent = TrainColors.violet;
    // The keyboard inset, so the sheet lifts its content above the keyboard
    // when the name field is focused.
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return ZivoSheetSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + keyboard),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: ZivoSheetHandle()),
                const SizedBox(height: 16),
                Text(
                  widget.existing == null
                      ? l(context).remindersNewTitle
                      : l(context).remindersEditTitle,
                  style: AppText.cardTitle.copyWith(fontSize: 19),
                ),
                const SizedBox(height: 18),

                // Kind.
                Row(
                  children: [
                    for (final kind in ReminderKind.values) ...[
                      _KindChip(
                        icon: reminderKindIcon(kind),
                        label: reminderKindLabel(context, kind),
                        accent: accent,
                        selected: _kind == kind,
                        onTap: () => setState(() => _kind = kind),
                      ),
                      if (kind != ReminderKind.values.last)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // Name.
                TextField(
                  controller: _label,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppText.rowTitle,
                  cursorColor: accent,
                  decoration: zivoFieldDecoration(
                    hintText: l(context).remindersLabelHint,
                    accent: accent,
                  ),
                ),
                const SizedBox(height: 18),

                // Time.
                _FieldLabel(l(context).remindersTimeLabel),
                const SizedBox(height: 8),
                _TimeButton(
                  label: formatClockTime(
                    context,
                    DateTime(2024, 1, 1, _time.hour, _time.minute),
                  ),
                  accent: accent,
                  onTap: _pickTime,
                ),
                const SizedBox(height: 18),

                // Repeat.
                _FieldLabel(l(context).remindersRepeatLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DayChip(
                      label: l(context).remindersEveryDay,
                      accent: accent,
                      selected: _isEveryDay,
                      onTap: () => setState(_weekdays.clear),
                    ),
                    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                      _DayChip(
                        label: weekdayShortLabel(context, d),
                        accent: accent,
                        selected: !_isEveryDay && _weekdays.contains(d),
                        onTap: () => _toggleDay(d),
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                TrainPrimaryButton(
                  label: l(context).remindersSave,
                  onTap: _save,
                ),
                if (widget.existing != null && widget.onDelete != null) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: _delete,
                      child: Text(
                        l(context).remindersDelete,
                        style: AppText.button.copyWith(color: TrainColors.ember),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppText.meta.copyWith(
      color: TrainColors.ink3,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : TrainColors.base,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : TrainColors.hairline,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? accent : TrainColors.inkAt(0.7),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.meta.copyWith(
                  color: selected ? accent : TrainColors.ink2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: TrainColors.base,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, size: 18, color: accent),
            const SizedBox(width: 12),
            Text(
              label,
              style: TrainType.mono(size: 16, color: TrainColors.inkPlain),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : TrainColors.base,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : TrainColors.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppText.meta.copyWith(
            color: selected ? accent : TrainColors.ink2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
