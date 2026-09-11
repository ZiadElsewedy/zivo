import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../../../diet/domain/diet_day.dart';
import '../../../diet/domain/diet_plan.dart';
import '../../../diet/domain/food_item.dart';
import '../../../diet/domain/meal.dart';
import '../../domain/notification_scheduler.dart';
import '../../domain/reminder.dart';
import '../../domain/reminder_notification_text.dart';
import '../../domain/reminder_sync.dart';
import '../../domain/workout_motivations.dart';
import '../reminder_labels.dart';
import '../workout_reminder_context.dart';

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
  final TextEditingController _addItem = TextEditingController();
  late ReminderKind _kind;
  late TimeOfDay _time;
  late Set<int> _weekdays;
  String? _emoji;

  // Meal sync: the chosen plan meal and its customised item lines.
  String? _mealLabel;
  List<String> _mealItems = [];

  // Workout sync: linked to the active plan (its text is resolved live), and
  // whether the notification shows encouragement instead of the exercise list —
  // and in which voice.
  bool _workoutLinked = false;
  bool _workoutMotivational = false;
  MotivationTone _tone = MotivationTone.gentle;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _label = TextEditingController(text: r?.label ?? '')
      // Keep the live preview in step with what the user is typing.
      ..addListener(_onFormChanged);
    _kind = r?.kind ?? ReminderKind.general;
    _time = r == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : TimeOfDay(hour: r.hour, minute: r.minute);
    _weekdays = {...?r?.weekdays};
    _emoji = r?.emoji;
    switch (r?.sync) {
      case MealSync m:
        _mealLabel = m.mealLabel;
        _mealItems = [...m.items];
      case WorkoutSync w:
        _workoutLinked = true;
        _workoutMotivational = w.motivational;
        _tone = w.tone;
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _addItem.dispose();
    super.dispose();
  }

  bool get _isEveryDay => _weekdays.isEmpty || _weekdays.length == 7;

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  void _selectKind(ReminderKind kind) => setState(() => _kind = kind);

  /// The sync this reminder would be saved with, given the current form — the
  /// same mapping as [_save], reused so the preview matches what will be stored.
  ReminderSync? _currentSync() {
    if (_kind == ReminderKind.meal && _mealLabel != null) {
      return MealSync(mealLabel: _mealLabel!, items: _mealItems);
    }
    if (_kind == ReminderKind.workout && _workoutLinked) {
      return WorkoutSync(motivational: _workoutMotivational, tone: _tone);
    }
    return null;
  }

  /// The live text the notification would carry right now — resolved through the
  /// very same `resolveReminderText` the scheduler uses, so the preview can't lie
  /// about what will fire.
  ({String title, String? body}) _previewText() {
    final reminder = Reminder.clamped(
      id: 'preview',
      label: _label.text,
      kind: _kind,
      hour: _time.hour,
      minute: _time.minute,
      sync: _currentSync(),
      emoji: _emoji,
    );
    return resolveReminderText(
      reminder,
      fallbackTitle: reminderKindLabel(context, _kind),
      context: _previewContext(),
    );
  }

  /// The workout context the preview resolves against: the active plan's next-up
  /// day, plus today's motivational line when that mode is on. Empty for
  /// non-workout or unsynced reminders (they need no context).
  ReminderContext _previewContext() {
    if (_kind != ReminderKind.workout || !_workoutLinked) {
      return ReminderContext.empty;
    }
    final plan = AppScope.of(context).workoutPlans.activePlan;
    final motivations = _workoutMotivational
        ? {_tone: _todaysMotivation(_tone)}
        : const <MotivationTone, String>{};
    return workoutReminderContext(plan, motivations: motivations);
  }

  /// Today's motivational line for [tone], seeded and localised exactly as the
  /// app root does when it bakes the real notification (see `app.dart`), so the
  /// preview shows the line that will actually fire today.
  String _todaysMotivation(MotivationTone tone) {
    final now = DateTime.now();
    final epochDay = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(2020)).inDays;
    final language = Localizations.localeOf(context).languageCode;
    return pickWorkoutMotivation(
      seed: epochDay,
      languageCode: language,
      tone: tone,
    );
  }

  Future<void> _pickTime() async {
    final brightness = Theme.of(context).brightness;
    var temp = _time;
    final picked = await showZivoSheet<TimeOfDay>(
      context: context,
      builder: (sheetContext) => ZivoSheetSurface(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Center(child: ZivoSheetHandle()),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                child: Row(
                  children: [
                    Text(
                      l(sheetContext).remindersTimeLabel,
                      style: AppText.cardTitle.copyWith(fontSize: 16),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(temp),
                      child: Text(
                        l(sheetContext).actionDone,
                        style: AppText.button.copyWith(
                          color: TrainColors.inkPlain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 216,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: brightness,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TrainType.mono(
                        size: 21,
                        color: TrainColors.inkPlain,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: MediaQuery.alwaysUse24HourFormatOf(sheetContext),
                    initialDateTime: DateTime(2024, 1, 1, _time.hour, _time.minute),
                    onDateTimeChanged: (dt) =>
                        temp = TimeOfDay(hour: dt.hour, minute: dt.minute),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
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

  /// The plan day whose meals to offer for syncing: the every-day template if
  /// the plan has one, else the day matching the reminder's first chosen weekday,
  /// else just the first day.
  DietDay? _dayForSync(DietPlan plan) {
    if (plan.days.isEmpty) return null;
    for (final d in plan.days) {
      if (d.weekday == null) return d;
    }
    if (!_isEveryDay) {
      final target = (_weekdays.toList()..sort()).first;
      for (final d in plan.days) {
        if (d.weekday == target) return d;
      }
    }
    return plan.days.first;
  }

  Future<void> _openMealPicker() async {
    final diet = AppScope.of(context).diet;
    final chosen = await showZivoSheet<Meal>(
      context: context,
      builder: (sheetContext) => _MealPickerSheet(
        stream: diet.watchActivePlan(),
        initial: diet.activePlan,
        resolveDay: _dayForSync,
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _mealLabel = chosen.label;
      _mealItems = [for (final item in chosen.items) foodItemLine(item)];
    });
  }

  void _addMealItem() {
    final text = _addItem.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _mealItems = [..._mealItems, text];
      _addItem.clear();
    });
  }

  void _removeMealItem(int index) =>
      setState(() => _mealItems = [..._mealItems]..removeAt(index));

  void _save() {
    ReminderSync? sync;
    if (_kind == ReminderKind.meal && _mealLabel != null) {
      sync = MealSync(mealLabel: _mealLabel!, items: _mealItems);
    } else if (_kind == ReminderKind.workout && _workoutLinked) {
      final nextDay = AppScope.of(context).workoutPlans.activePlan?.nextDay;
      sync = WorkoutSync(
        cachedDayLabel: nextDay?.label,
        motivational: _workoutMotivational,
      );
    }
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
      sync: sync,
      emoji: _emoji,
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
    // The keyboard inset, so the sheet lifts its content above the keyboard
    // when the name field is focused.
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final preview = _previewText();
    final previewTime = formatClockTime(
      context,
      DateTime(2024, 1, 1, _time.hour, _time.minute),
    );
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.existing == null
                            ? l(context).remindersNewTitle
                            : l(context).remindersEditTitle,
                        style: AppText.cardTitle.copyWith(fontSize: 19),
                      ),
                    ),
                    _SheetCloseButton(
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Kind.
                Row(
                  children: [
                    for (final kind in ReminderKind.values) ...[
                      _KindChip(
                        icon: reminderKindIcon(kind),
                        label: reminderKindLabel(context, kind),
                        selected: _kind == kind,
                        onTap: () => _selectKind(kind),
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
                  cursorColor: TrainColors.inkPlain,
                  decoration: zivoFieldDecoration(
                    hintText: l(context).remindersLabelHint,
                    accent: TrainColors.neutralMark,
                  ),
                ),

                // Emoji — optional, leads the row and the notification title.
                const SizedBox(height: 16),
                _FieldLabel(l(context).remindersEmoji),
                const SizedBox(height: 8),
                _EmojiPicker(
                  selected: _emoji,
                  onSelected: (e) => setState(() => _emoji = e),
                ),

                // Sync — meal or workout.
                if (_kind == ReminderKind.meal) ...[
                  const SizedBox(height: 18),
                  _MealSyncSection(
                    mealLabel: _mealLabel,
                    items: _mealItems,
                    addController: _addItem,
                    onSync: _openMealPicker,
                    onAddItem: _addMealItem,
                    onRemoveItem: _removeMealItem,
                  ),
                ] else if (_kind == ReminderKind.workout) ...[
                  const SizedBox(height: 18),
                  _WorkoutSyncSection(
                    linked: _workoutLinked,
                    motivational: _workoutMotivational,
                    tone: _tone,
                    onChanged: (v) => setState(() => _workoutLinked = v),
                    onMotivationalChanged: (v) =>
                        setState(() => _workoutMotivational = v),
                    onToneChanged: (t) => setState(() => _tone = t),
                  ),
                ],
                const SizedBox(height: 18),

                // Preview — the exact title/body the notification will carry,
                // resolved through the same code path as the real schedule.
                _FieldLabel(l(context).remindersPreview),
                const SizedBox(height: 8),
                _NotificationPreview(
                  title: preview.title,
                  body: preview.body ?? l(context).remindersPreviewEmptyBody,
                  hasBody: preview.body != null,
                  time: previewTime,
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
                      selected: _isEveryDay,
                      onTap: () => setState(_weekdays.clear),
                    ),
                    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                      _DayChip(
                        label: weekdayShortLabel(context, d),
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

/// A food item as one line for a synced meal reminder: "Chicken 200 g".
String foodItemLine(FoodItem item) {
  final qty = item.quantity;
  final amount = qty == qty.roundToDouble()
      ? qty.toInt().toString()
      : qty.toString();
  final unit = item.unit.trim();
  return unit.isEmpty ? item.name : '${item.name} $amount $unit';
}

/// A curated emoji picker — a "none" chip plus a row of reminder-friendly
/// glyphs. Deliberately a small preset set, not the system keyboard: one tap to
/// a sensible mark, and every option renders identically across platforms.
class _EmojiPicker extends StatelessWidget {
  const _EmojiPicker({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  // Fitness-, meal- and time-flavoured, in that rough order.
  static const _presets = [
    '💪', '🏋️', '🏃', '🧘', '🔥', '🎯',
    '🥗', '🍎', '💧', '☕', '😴', '⏰',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _EmojiChip(
          selected: selected == null,
          onTap: () => onSelected(null),
          child: Icon(
            AppIcons.close,
            size: 16,
            color: selected == null ? TrainColors.base : TrainColors.ink3,
          ),
        ),
        for (final emoji in _presets)
          _EmojiChip(
            selected: selected == emoji,
            onTap: () => onSelected(emoji),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
      ],
    );
  }
}

class _EmojiChip extends StatelessWidget {
  const _EmojiChip({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? TrainColors.inkPlain : TrainColors.base,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? TrainColors.inkPlain : TrainColors.hairline,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A lock-screen-style preview of the notification this reminder will post —
/// the app tile, ZIVO, the fire time, and the resolved title/body. [hasBody]
/// is false when the reminder has no second line, so the placeholder copy reads
/// as a hint rather than real content.
class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({
    required this.title,
    required this.body,
    required this.hasBody,
    required this.time,
  });

  final String title;
  final String body;
  final bool hasBody;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TrainColors.base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: TrainColors.ember,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(AppIcons.reminders, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ZIVO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.meta.copyWith(
                          color: TrainColors.ink3,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Text(
                      ltrFor(context, time),
                      style: AppText.meta.copyWith(color: TrainColors.ink3),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isolate(title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isolate(body),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(
                    color: hasBody ? TrainColors.ink2 : TrainColors.ink3,
                    height: 1.35,
                    fontStyle: hasBody ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable close affordance in the sheet header — the reliable way out when
/// a tall, keyboard-lifted sheet fills the screen and leaves no scrim to tap.
class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: l(context).actionClose,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TrainColors.base,
            shape: BoxShape.circle,
            border: Border.all(color: TrainColors.hairline),
          ),
          child: Icon(AppIcons.close, size: 16, color: TrainColors.ink2),
        ),
      ),
    );
  }
}

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

/// The meal-sync block: a Sync button, and — once a meal is chosen — its
/// customisable item list. Editing here shapes only the reminder, never the plan.
class _MealSyncSection extends StatelessWidget {
  const _MealSyncSection({
    required this.mealLabel,
    required this.items,
    required this.addController,
    required this.onSync,
    required this.onAddItem,
    required this.onRemoveItem,
  });

  final String? mealLabel;
  final List<String> items;
  final TextEditingController addController;
  final VoidCallback onSync;
  final VoidCallback onAddItem;
  final ValueChanged<int> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SyncButton(
          label: mealLabel == null
              ? l(context).remindersSyncFromPlan
              : isolate(mealLabel!),
          onTap: onSync,
        ),
        if (mealLabel != null) ...[
          const SizedBox(height: 14),
          _FieldLabel(l(context).remindersMealItems),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MealItemRow(
                label: ltrFor(context, items[i]),
                onRemove: () => onRemoveItem(i),
              ),
            ),
          _AddItemField(
            controller: addController,
            onSubmit: onAddItem,
          ),
        ],
      ],
    );
  }
}

class _MealItemRow extends StatelessWidget {
  const _MealItemRow({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: TrainColors.base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrainType.ui(size: 14, color: TrainColors.inkPlain),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 16, color: TrainColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _AddItemField extends StatelessWidget {
  const _AddItemField({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      style: AppText.rowTitle.copyWith(fontSize: 14),
      cursorColor: TrainColors.inkPlain,
      onSubmitted: (_) => onSubmit(),
      decoration: zivoFieldDecoration(
        hintText: l(context).remindersAddItem,
        accent: TrainColors.neutralMark,
      ).copyWith(
        suffixIcon: IconButton(
          onPressed: onSubmit,
          icon: Icon(AppIcons.add, size: 18, color: TrainColors.neutralMark),
        ),
      ),
    );
  }
}

/// The workout-sync block: the sync toggle plus its explanation, and — once
/// synced — a nested "motivational message" toggle that swaps the exercise list
/// for a line of encouragement.
class _WorkoutSyncSection extends StatelessWidget {
  const _WorkoutSyncSection({
    required this.linked,
    required this.motivational,
    required this.tone,
    required this.onChanged,
    required this.onMotivationalChanged,
    required this.onToneChanged,
  });
  final bool linked;
  final bool motivational;
  final MotivationTone tone;
  final ValueChanged<bool> onChanged;
  final ValueChanged<bool> onMotivationalChanged;
  final ValueChanged<MotivationTone> onToneChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: TrainColors.base,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.reminderSync, size: 18, color: TrainColors.neutralMark),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l(context).remindersSyncWorkout,
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                  ),
                ),
              ),
              Switch.adaptive(value: linked, onChanged: onChanged),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 30, end: 8, top: 2),
            child: Text(
              l(context).remindersSyncWorkoutHint,
              style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
            ),
          ),
          if (linked) ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 30, top: 12),
              child: Divider(height: 1, color: TrainColors.hairline),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 30, top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l(context).remindersMotivational,
                      style: TrainType.ui(
                        size: 15,
                        weight: FontWeight.w700,
                        color: TrainColors.inkPlain,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: motivational,
                    onChanged: onMotivationalChanged,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 30, end: 8, top: 2),
              child: Text(
                l(context).remindersMotivationalHint,
                style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
              ),
            ),
            if (motivational)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 30, top: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in MotivationTone.values)
                      _DayChip(
                        label: motivationToneLabel(context, t),
                        selected: tone == t,
                        onTap: () => onToneChanged(t),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: TrainColors.base,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Row(
          children: [
            Icon(AppIcons.reminderSync, size: 18, color: TrainColors.neutralMark),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TrainType.ui(
                  size: 15,
                  weight: FontWeight.w700,
                  color: TrainColors.inkPlain,
                ),
              ),
            ),
            Icon(AppIcons.chevron, size: 16, color: TrainColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// The meal picker sheet: lists the regular meals of the plan day to sync from.
class _MealPickerSheet extends StatelessWidget {
  const _MealPickerSheet({
    required this.stream,
    required this.initial,
    required this.resolveDay,
  });

  final Stream<DietPlan?> stream;
  final DietPlan? initial;
  final DietDay? Function(DietPlan) resolveDay;

  @override
  Widget build(BuildContext context) {
    return ZivoSheetSurface(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: StreamBuilder<DietPlan?>(
            stream: stream,
            initialData: initial,
            builder: (context, snapshot) {
              final plan = snapshot.data;
              final day = plan == null ? null : resolveDay(plan);
              final meals = day == null ? const <Meal>[] : regularMeals(day.meals);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: ZivoSheetHandle()),
                  const SizedBox(height: 16),
                  Text(
                    l(context).remindersPickMeal,
                    style: AppText.cardTitle.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  if (meals.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l(context).remindersNoMealPlan,
                        style: AppText.meta.copyWith(
                          color: TrainColors.ink3,
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    for (final meal in meals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _MealOption(
                          meal: meal,
                          onTap: () => Navigator.of(context).pop(meal),
                        ),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MealOption extends StatelessWidget {
  const _MealOption({required this.meal, required this.onTap});
  final Meal meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = meal.items.length;
    final subtitle = meal.items
        .take(3)
        .map((i) => i.name)
        .where((n) => n.trim().isNotEmpty)
        .join(' · ');
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
            Icon(AppIcons.reminderMeal, size: 20, color: TrainColors.neutralMark),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isolate(meal.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w700,
                      color: TrainColors.inkPlain,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.meta.copyWith(color: TrainColors.ink3),
                    ),
                  ],
                ],
              ),
            ),
            Icon(AppIcons.chevron, size: 16, color: TrainColors.ink3),
          ],
        ),
      ),
    );
  }
}

/// A kind selector: a crisp segmented control — the selected chip is a solid ink
/// fill (no hue), the rest an outlined surface. Deliberately monochrome.
class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? TrainColors.base : TrainColors.ink2;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? TrainColors.inkPlain : TrainColors.base,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? TrainColors.inkPlain : TrainColors.hairline,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.meta.copyWith(
                  color: fg,
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
  const _TimeButton({required this.label, required this.onTap});

  final String label;
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
            Icon(Icons.access_time_rounded, size: 18, color: TrainColors.neutralMark),
            const SizedBox(width: 12),
            Text(
              ltrFor(context, label),
              style: TrainType.mono(size: 16, color: TrainColors.inkPlain),
            ),
          ],
        ),
      ),
    );
  }
}

/// A repeat-day chip — the same monochrome segmented treatment as the kind chips.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? TrainColors.inkPlain : TrainColors.base,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? TrainColors.inkPlain : TrainColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: AppText.meta.copyWith(
            color: selected ? TrainColors.base : TrainColors.ink2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
