import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/rep_target.dart';
import '../../domain/set_type.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../../domain/workout_plan_source.dart';
import '../../domain/workout_plan_status.dart';
import '../../domain/workout_set.dart';
import '../widgets/staggered_reveal.dart';

/// The next cycle slot letter for a plan that already has [count] days: A, B,
/// C… (falls back to a number past Z).
String _slotForIndex(int count) =>
    count < 26 ? String.fromCharCode(0x41 + count) : '${count + 1}';

/// "60" / "22.5" — a weight without a trailing ".0".
String _trimWeight(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// A custom "lift" for drag-reordered items (day tiles, exercise rows) —
/// scales up slightly, gains elevation/shadow, and dims a touch while being
/// dragged, replacing [ReorderableListView]'s plain default proxy (a flat
/// `Material` with no real weight to it). [animation] is driven by
/// [ReorderableListView] itself (0 at pickup/drop, ~1 while actively
/// dragging) — the internal reflow/settle timing isn't swappable for a
/// custom spring via the public API, but it's already a smooth transition,
/// not an instant snap. Reduced motion drops the lift flourish entirely
/// (the reorder itself stays fully functional either way).
Widget _liftProxyDecorator(
  Widget child,
  Animation<double> animation, {
  required double radius,
}) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, builtChild) {
      if (reducedMotion(context)) return builtChild!;
      final t = animation.value;
      return Transform.scale(
        scale: 1.0 + 0.03 * t,
        child: Material(
          color: Colors.transparent,
          elevation: 10 * t,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(radius),
          child: Opacity(opacity: 1 - 0.05 * t, child: builtChild!),
        ),
      );
    },
    child: child,
  );
}

/// A mutable day while editing — its exercises are fully-formed
/// [PlannedExercise]s (built by the exercise sheet), so drafts round-trip
/// losslessly through save.
class _DayDraft {
  _DayDraft({
    required this.id,
    required this.slot,
    required this.label,
    this.notes,
    List<PlannedExercise>? exercises,
  }) : exercises = exercises ?? <PlannedExercise>[];

  final String id;
  final String slot;
  final String label;
  final String? notes;
  final List<PlannedExercise> exercises;
}

/// Create or edit the workout plan — name, days (slot + label), and exercises
/// within a day (added or edited in place via a sheet that captures a compact
/// set spec and generates the working sets). Saving persists the whole plan,
/// reusing its id when editing so it overwrites idempotently, and preserving
/// the rotation cursor. Dark, matching the session/plan/history screens on
/// the app-wide [TrainColors] theme.
class WorkoutPlanEditPage extends StatefulWidget {
  const WorkoutPlanEditPage({
    super.key,
    this.initialPlan,
    this.asSplit = false,
  });

  final WorkoutPlan? initialPlan;

  /// Reached from split management rather than the single-active-plan flow —
  /// saves/deletes go through [WorkoutPlanRepository.saveSplit]/[deleteSplit]
  /// instead of [savePlan]/[deletePlan], so creating or editing a split here
  /// never silently steals the active pointer (`saveSplit` only activates
  /// when nothing is active yet; `savePlan` always would). Everything else —
  /// the day/exercise builder itself — is identical either way, per
  /// WORKOUT_SYSTEM.md Phase 4's "reuse the plan editor."
  final bool asSplit;

  @override
  State<WorkoutPlanEditPage> createState() => _WorkoutPlanEditPageState();
}

class _WorkoutPlanEditPageState extends State<WorkoutPlanEditPage> {
  late final TextEditingController _name;
  late final String _planId;
  late final DateTime _createdAt;

  /// The id of the day the plan's rotation cursor pointed at when editing
  /// opened — null for a new plan (nothing to preserve; a fresh plan just
  /// starts its rotation at day 0, same as before). Tracked by IDENTITY
  /// rather than the raw index [WorkoutPlan.cycleCursor] stores, so
  /// reordering days (see `_reorderDays`) keeps the rotation pointed at the
  /// SAME logical "next day" in its new position — reordering must never
  /// silently scramble which workout Home/the Workout page show as next.
  /// Recomputed back to an index in [_save].
  late final String? _cursorDayId;
  final List<_DayDraft> _days = [];
  bool _canSave = false;

  /// Day/exercise ids mid-way through their remove animation — still present
  /// in [_days] (so [_recompute]/save stay correct if the removal is somehow
  /// interrupted) but rendered as collapsing/fading rather than gone
  /// instantly. See [_removeDay]/[_removeExercise].
  final Set<String> _removingDayIds = {};
  final Set<String> _removingExerciseIds = {};

  /// Days added during this editing session — they start expanded (see
  /// `_DayCard.initiallyExpanded`), since adding a day is immediately
  /// followed by adding exercises to it. Days loaded from an existing plan
  /// start collapsed. Membership only matters the moment a `_DayCard`'s
  /// State is first created for that id (its `late` initializer reads it
  /// once) — never removed, harmless to keep growing.
  final Set<String> _autoExpandDayIds = {};

  bool get _editing => widget.initialPlan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.initialPlan;
    _name = TextEditingController(text: plan?.name ?? '');
    _planId = plan?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _createdAt = plan?.createdAt ?? DateTime.now();
    _cursorDayId = (plan == null || plan.days.isEmpty)
        ? null
        : plan.days
              .firstWhere(
                (d) => d.order == plan.cycleCursor,
                orElse: () => plan.days.first,
              )
              .id;
    if (plan != null) {
      _days.addAll(
        plan.days.map(
          (d) => _DayDraft(
            id: d.id,
            slot: d.slot,
            label: d.label,
            notes: d.notes,
            exercises: List.of(d.exercises),
          ),
        ),
      );
    }
    _name.addListener(_recompute);
    _recompute();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _recompute() {
    final canSave = _name.text.trim().isNotEmpty && _days.isNotEmpty;
    if (canSave != _canSave) setState(() => _canSave = canSave);
  }

  Future<void> _addDay() async {
    final result = await showModalBottomSheet<_DayDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DaySheet(suggestedSlot: _slotForIndex(_days.length)),
    );
    if (result == null) return;
    HapticFeedback.lightImpact();
    _autoExpandDayIds.add(result.id);
    setState(() => _days.add(result));
    _recompute();
  }

  /// Plays a brief collapse/fade (see the day row's `AnimatedSize` +
  /// `AnimatedOpacity` in `build`) before actually removing the day, so it
  /// reads as a row shrinking away rather than an instant pop — a
  /// destructive action, hence `mediumImpact` (mirrors the chat-delete swipe
  /// threshold's role: the moment commitment becomes certain).
  Future<void> _removeDay(int index) async {
    final day = _days[index];
    HapticFeedback.mediumImpact();
    if (reducedMotion(context)) {
      setState(() => _days.removeWhere((d) => d.id == day.id));
      _recompute();
      return;
    }
    setState(() => _removingDayIds.add(day.id));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() {
      _removingDayIds.remove(day.id);
      _days.removeWhere((d) => d.id == day.id);
    });
    _recompute();
  }

  /// Long-press-drag reorder for days — wired to `onReorderItem`, so
  /// [newIndex] already arrives as the final insert position (no manual
  /// removal-adjustment needed; that's the whole point of `onReorderItem`
  /// over the older, deprecated `onReorder`). Rotation-cursor identity (see
  /// [_cursorDayId]) is untouched here — it's resolved back to an index
  /// from the day's id in [_save], so it follows wherever that day ends up.
  void _reorderDays(int oldIndex, int newIndex) {
    setState(() {
      final day = _days.removeAt(oldIndex);
      _days.insert(newIndex, day);
    });
  }

  Future<void> _addExercise(int dayIndex) async {
    final exercise = await showModalBottomSheet<PlannedExercise>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ExerciseSheet(),
    );
    if (exercise == null) return;
    HapticFeedback.lightImpact();
    setState(() => _days[dayIndex].exercises.add(exercise));
  }

  /// Opens the exercise sheet pre-filled with the exercise already at
  /// [exerciseIndex] and, on save, replaces it in place — the whole point
  /// being that editing an exercise no longer means deleting and re-adding
  /// it (which loses its position in the day and its id).
  Future<void> _editExercise(int dayIndex, int exerciseIndex) async {
    final current = _days[dayIndex].exercises[exerciseIndex];
    final exercise = await showModalBottomSheet<PlannedExercise>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExerciseSheet(initial: current),
    );
    if (exercise == null) return;
    setState(() => _days[dayIndex].exercises[exerciseIndex] = exercise);
  }

  /// Same collapse-before-remove treatment as [_removeDay], scoped to one
  /// exercise row within a day.
  Future<void> _removeExercise(int dayIndex, int exerciseIndex) async {
    final day = _days[dayIndex];
    final exercise = day.exercises[exerciseIndex];
    HapticFeedback.mediumImpact();
    if (reducedMotion(context)) {
      setState(() => day.exercises.removeWhere((e) => e.id == exercise.id));
      return;
    }
    setState(() => _removingExerciseIds.add(exercise.id));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() {
      _removingExerciseIds.remove(exercise.id);
      day.exercises.removeWhere((e) => e.id == exercise.id);
    });
  }

  /// Long-press-drag reorder for exercises within one day — same
  /// `onReorderItem` convention as [_reorderDays] (newIndex already final).
  void _reorderExercises(int dayIndex, int oldIndex, int newIndex) {
    setState(() {
      final exercises = _days[dayIndex].exercises;
      final exercise = exercises.removeAt(oldIndex);
      exercises.insert(newIndex, exercise);
    });
  }

  /// The wheel's seed when opening the default-rest sheet — the first
  /// exercise's own rest if there is one, so re-opening it after already
  /// bulk-setting a value starts from that value rather than always 1:30.
  int _currentSeedRest() {
    for (final day in _days) {
      for (final exercise in day.exercises) {
        return exercise.defaultRestSeconds;
      }
    }
    return 90;
  }

  /// Sets EVERY exercise's rest, across every day, to one chosen value —
  /// the bulk counterpart to the per-exercise override in [_editExercise].
  /// Per-exercise overrides made *after* this still stick; a later bulk
  /// apply overwrites them again, same as re-running any bulk action.
  Future<void> _pickDefaultRest() async {
    final seconds = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DefaultRestSheet(initialSeconds: _currentSeedRest()),
    );
    if (seconds == null) return;
    setState(() {
      for (final day in _days) {
        for (var i = 0; i < day.exercises.length; i++) {
          final exercise = day.exercises[i];
          day.exercises[i] = exercise.copyWith(
            defaultRestSeconds: seconds,
            sets: [
              for (final set in exercise.sets)
                set.copyWith(restSeconds: seconds),
            ],
          );
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final days = <WorkoutDay>[];
    for (var i = 0; i < _days.length; i++) {
      final draft = _days[i];
      days.add(
        WorkoutDay(
          id: draft.id,
          slot: draft.slot,
          label: draft.label,
          notes: draft.notes,
          order: i,
          exercises: [
            for (var j = 0; j < draft.exercises.length; j++)
              draft.exercises[j].copyWith(order: j),
          ],
        ),
      );
    }
    // Follow the SAME day the cursor pointed at through any reorder — not
    // a fixed index. Falls back to day 0 for a new plan (nothing to
    // preserve) or if that day was removed since (nothing sensible left to
    // point at).
    final cursorIndex = _cursorDayId == null
        ? -1
        : days.indexWhere((d) => d.id == _cursorDayId);
    final plan = WorkoutPlan(
      id: _planId,
      name: _name.text.trim(),
      status: WorkoutPlanStatus.active,
      // Preserves an imported draft's `pdf` marker through the mandatory
      // review step (WORKOUT_SYSTEM.md §3.4) — only a genuinely new plan
      // (no initialPlan) defaults to `manual`.
      source: widget.initialPlan?.source ?? WorkoutPlanSource.manual,
      createdAt: _createdAt,
      updatedAt: now,
      cycleCursor: days.isEmpty ? 0 : (cursorIndex >= 0 ? cursorIndex : 0),
      days: days,
    );
    final plans = AppScope.of(context).workoutPlans;
    if (widget.asSplit) {
      await plans.saveSplit(plan);
    } else {
      await plans.savePlan(plan);
    }
    if (mounted) Navigator.of(context).pop(plan);
  }

  Future<void> _delete() async {
    final plan = widget.initialPlan;
    if (plan == null) return;
    final plans = AppScope.of(context).workoutPlans;
    final noun = widget.asSplit ? 'split' : 'plan';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0x08FFFFFF),
        title: Text(
          'Delete this $noun?',
          style: TrainType.ui(
            size: 20,
            weight: FontWeight.w800,
            tracking: -0.025,
            height: 1.15,
            color: TrainColors.ink,
          ),
        ),
        content: Text(
          'This removes "${plan.name}" and all its days and exercises. This can\'t be undone.',
          style: TrainType.ui(
            size: 13.5,
            weight: FontWeight.w400,
            height: 1.5,
            color: TrainColors.ink2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TrainType.ui(
                size: 15,
                weight: FontWeight.w700,
                height: 1,
                color: TrainColors.ink4,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context, true);
            },
            child: Text(
              'Delete',
              style: TrainType.ui(
                size: 15,
                weight: FontWeight.w700,
                height: 1,
                color: TrainColors.ember,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.asSplit) {
      await plans.deleteSplit(plan.id);
    } else {
      await plans.deletePlan(plan.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: DecoratedBox(
        // The same wash the Workout hub carries — a capture flow belongs to
        // the surface that launched it, not to a flat void.
        decoration: const BoxDecoration(gradient: TrainColors.hubTint),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CaptureTopBar(
                title: _editing
                    ? (widget.asSplit ? 'Edit split' : 'Edit workout plan')
                    : (widget.asSplit ? 'New split' : 'New workout plan'),
                onClose: () => Navigator.of(context).maybePop(),
                titleColor: TrainColors.ink2,
                iconColor: TrainColors.ink2,
                chipColor: TrainColors.glassStrong,
                trailing: _editing
                    ? CaptureIconButton(
                        key: const Key('workout-plan-delete'),
                        icon: Icons.delete_outline_rounded,
                        onTap: _delete,
                        semanticLabel: widget.asSplit
                            ? 'Delete split'
                            : 'Delete plan',
                        iconColor: TrainColors.ember,
                        chipColor: TrainColors.glassStrong,
                      )
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
                child: TextField(
                  key: const Key('plan-name-field'),
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  cursorColor: TrainColors.green,
                  style: TrainType.ui(
                    size: 24,
                    weight: FontWeight.w800,
                    tracking: -0.025,
                    height: 1.15,
                    color: TrainColors.ink,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Plan name',
                    hintStyle: TrainType.ui(
                      size: 24,
                      weight: FontWeight.w800,
                      tracking: -0.025,
                      height: 1.15,
                      color: TrainColors.ink4,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
                child: _DefaultRestRow(
                  seconds: _currentSeedRest(),
                  onTap: _pickDefaultRest,
                ),
              ),
              Expanded(
                child: _days.isEmpty
                    ? _EmptyDays(onAdd: _addDay)
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
                        itemCount: _days.length + 1,
                        // Default handles would make the WHOLE row (including
                        // the trailing "Add day" button) a drag target; days
                        // opt in individually via ReorderableDelayedDragStartListener
                        // below instead, and the add-button — outside that
                        // wrapper — is never draggable.
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, animation) =>
                            _liftProxyDecorator(child, animation, radius: 18),
                        onReorderStart: (_) => HapticFeedback.selectionClick(),
                        onReorderEnd: (_) => HapticFeedback.lightImpact(),
                        onReorderItem: (oldIndex, newIndex) {
                          // Guards the trailing "Add day" item defensively —
                          // it always sits at _days.length and, since only
                          // day items are wrapped in a drag-start listener
                          // (see buildDefaultDragHandles above), never
                          // actually starts a drag in the first place.
                          if (oldIndex >= _days.length) return;
                          _reorderDays(oldIndex, newIndex);
                        },
                        itemBuilder: (context, i) {
                          if (i == _days.length) {
                            return _AddButton(
                              key: const ValueKey('add-day-button'),
                              label: 'Add day',
                              onTap: _addDay,
                            );
                          }
                          final day = _days[i];
                          final removing = _removingDayIds.contains(day.id);
                          final reduced = reducedMotion(context);
                          return Padding(
                            // Keyed on the day's stable id so both its expand
                            // state (owned by _DayCardState) and its
                            // reorderable identity survive parent rebuilds
                            // from unrelated edits, rather than being
                            // recreated fresh (and re-collapsed) every time.
                            key: ValueKey(day.id),
                            padding: const EdgeInsets.only(bottom: 10),
                            // Collapse-before-remove (see _removeDay) — the
                            // AnimatedSize/AnimatedOpacity pair the removal
                            // itself is timed against. StaggeredReveal handles
                            // the opposite edge (a freshly-added day easing in
                            // rather than popping), reusing the same widget
                            // every other list on this feature already uses.
                            child: AnimatedSize(
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              curve: Curves.easeIn,
                              alignment: Alignment.topCenter,
                              child: AnimatedOpacity(
                                opacity: removing ? 0 : 1,
                                duration: reduced
                                    ? Duration.zero
                                    : const Duration(milliseconds: 200),
                                child: removing
                                    ? const SizedBox(width: double.infinity)
                                    : StaggeredReveal(
                                        index: i,
                                        child:
                                            ReorderableDelayedDragStartListener(
                                              index: i,
                                              child: _DayCard(
                                                day: day,
                                                onRemoveDay: () =>
                                                    _removeDay(i),
                                                onAddExercise: () =>
                                                    _addExercise(i),
                                                onEditExercise: (ei) =>
                                                    _editExercise(i, ei),
                                                onRemoveExercise: (ei) =>
                                                    _removeExercise(i, ei),
                                                onReorderExercise: (oi, ni) =>
                                                    _reorderExercises(
                                                      i,
                                                      oi,
                                                      ni,
                                                    ),
                                                removingExerciseIds:
                                                    _removingExerciseIds,
                                                initiallyExpanded:
                                                    _autoExpandDayIds.contains(
                                                      day.id,
                                                    ),
                                              ),
                                            ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  8,
                  18,
                  MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 8,
                ),
                child: PillButton(
                  label: 'Save plan',
                  icon: Icons.check_rounded,
                  color: TrainColors.ember,
                  enabled: _canSave,
                  onTap: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDays extends StatelessWidget {
  const _EmptyDays({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.fitness_center_rounded,
            size: 30,
            color: TrainColors.ink4,
          ),
          const SizedBox(height: 12),
          Text(
            'No days yet.',
            style: TrainType.ui(
              size: 14,
              weight: FontWeight.w400,
              height: 1.5,
              color: TrainColors.ink2,
            ),
          ),
          const SizedBox(height: 14),
          _AddButton(label: 'Add day', onTap: onAdd),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.label,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 18,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: TrainColors.hairline, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quiet, not green: "Add day"/"Add exercise" sit above this
              // screen's real commit ("Save plan"), and two coloured actions
              // competing is the "one committing action" rule being broken.
              Icon(
                Icons.add_rounded,
                size: compact ? 14 : 17,
                color: const Color(0x99F4F4F0),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TrainType.ui(
                  size: compact ? 12.5 : 14,
                  weight: FontWeight.w700,
                  height: 1,
                  color: const Color(0xCCF4F4F0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The discoverable bulk-rest control — "where's Edit Rest" for the whole
/// plan at once. Shows the value it'll apply so it reads as a real control,
/// not a mystery button.
class _DefaultRestRow extends StatelessWidget {
  const _DefaultRestRow({required this.seconds, required this.onTap});

  final int seconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TrainColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: TrainColors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Default rest · ${restLabel(seconds)}',
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w600,
                      height: 1.1,
                      color: TrainColors.ink,
                    ),
                  ),
                ),
                Text(
                  'Set all',
                  style: TrainType.mono(
                    size: 10.5,
                    weight: FontWeight.w600,
                    tracking: 0.06,
                    color: TrainColors.green,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: TrainColors.ink4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bulk-rest sheet — the same dark [_RestPicker] wheel used for a single
/// exercise's rest, but its result applies to every exercise in the plan at
/// once (see [_WorkoutPlanEditPageState._pickDefaultRest]).
class _DefaultRestSheet extends StatefulWidget {
  const _DefaultRestSheet({required this.initialSeconds});

  final int initialSeconds;

  @override
  State<_DefaultRestSheet> createState() => _DefaultRestSheetState();
}

class _DefaultRestSheetState extends State<_DefaultRestSheet> {
  late int _seconds = widget.initialSeconds;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Default rest',
      children: [
        Text(
          'Sets every exercise in this plan to this rest. Editing one exercise '
          'afterward still overrides it individually.',
          style: TrainType.ui(
            size: 13.5,
            weight: FontWeight.w400,
            height: 1.5,
            color: TrainColors.ink2,
          ),
        ),
        const SizedBox(height: 16),
        _RestPicker(initialSeconds: _seconds, onChanged: (v) => _seconds = v),
        const SizedBox(height: 22),
        PillButton(
          label: 'Set all',
          icon: Icons.check_rounded,
          color: TrainColors.ember,
          enabled: true,
          onTap: () => Navigator.of(context).pop(_seconds),
        ),
      ],
    );
  }
}

/// A collapsible day tile — collapsed shows just the header (day title +
/// exercise count); tapping the header springs it open to reveal the
/// exercise list (notes, rows, "Add exercise"). Exists so editing a plan
/// with many days doesn't mean scrolling past every prior day's full
/// exercise list to reach the last one — collapsed, each day is one glance.
///
/// Multiple days can be open at once (deliberately not a forced accordion —
/// useful when cross-referencing two days while editing, e.g. copying a
/// rest value). Expand state lives in this State object, keyed by the
/// caller on the day's stable id ([_DayDraft.id]), so it survives parent
/// rebuilds (editing/removing a DIFFERENT day, or an exercise within this
/// one) without collapsing back — re-expanding after an edit would be a
/// regression, not a feature.
class _DayCard extends StatefulWidget {
  const _DayCard({
    required this.day,
    required this.onRemoveDay,
    required this.onAddExercise,
    required this.onEditExercise,
    required this.onRemoveExercise,
    required this.onReorderExercise,
    required this.removingExerciseIds,
    this.initiallyExpanded = false,
  });

  final _DayDraft day;
  final VoidCallback onRemoveDay;
  final VoidCallback onAddExercise;
  final void Function(int exerciseIndex) onEditExercise;
  final void Function(int exerciseIndex) onRemoveExercise;
  final void Function(int oldIndex, int newIndex) onReorderExercise;

  /// Exercise ids mid-collapse — see [_WorkoutPlanEditPageState._removeExercise].
  final Set<String> removingExerciseIds;

  /// Only meaningful the first time this State is created for a given key —
  /// a day the caller just added (see `_WorkoutPlanEditPageState._addDay`)
  /// starts open, since the user is clearly about to add exercises to it;
  /// every other day starts collapsed.
  final bool initiallyExpanded;

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.initiallyExpanded ? 1 : 0,
  );

  void _toggle() {
    final target = _expanded ? 0.0 : 1.0;
    setState(() => _expanded = !_expanded);
    if (reducedMotion(context)) {
      _controller.value = target;
    } else {
      // Critically damped, no bounce — this is a disclosure, not a
      // momentum-driven gesture. Always retargets from the controller's
      // live value, so tapping again mid-animation reverses smoothly
      // instead of jumping.
      _controller.springTo(target, spring: AppSprings.standard);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final count = day.exercises.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressableScale(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Day ${day.slot} · ${day.label}',
                            style: TrainType.ui(
                              size: 15,
                              weight: FontWeight.w600,
                              height: 1.1,
                              color: TrainColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$count exercise${count == 1 ? '' : 's'}',
                            style: TrainType.mono(
                              size: 10.5,
                              tracking: 0.06,
                              color: TrainColors.ink4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => Transform.rotate(
                        angle: _controller.value * math.pi,
                        child: child,
                      ),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: TrainColors.ink4,
                      ),
                    ),
                    PressableScale(
                      child: IconButton(
                        onPressed: widget.onRemoveDay,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: TrainColors.ink4,
                        ),
                        splashRadius: 20,
                        tooltip: 'Remove day',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              // Fully collapsed and at rest — skip the subtree entirely
              // rather than just squashing it to zero height, so a
              // collapsed day's exercises are genuinely absent (not
              // present-but-invisible/still-hit-testable). Gated on
              // `!_controller.isAnimating`, not an exact `value == 0` check
              // — a settled SpringSimulation can land at a tiny residual
              // (within its tolerance) rather than precisely 0.
              if (!_expanded && !_controller.isAnimating) {
                return const SizedBox.shrink();
              }
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _controller.value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (day.notes != null && day.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      day.notes!,
                      style: TrainType.mono(
                        size: 10.5,
                        tracking: 0.06,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ),
                if (day.exercises.isNotEmpty)
                  ReorderableListView.builder(
                    // Nested inside the page's own scrollable — sizes
                    // itself to its (typically short) exercise list rather
                    // than trying to scroll independently.
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) =>
                        _liftProxyDecorator(child, animation, radius: 14),
                    onReorderStart: (_) => HapticFeedback.selectionClick(),
                    onReorderEnd: (_) => HapticFeedback.lightImpact(),
                    onReorderItem: widget.onReorderExercise,
                    itemCount: day.exercises.length,
                    itemBuilder: (context, ei) {
                      final exercise = day.exercises[ei];
                      final removing = widget.removingExerciseIds.contains(
                        exercise.id,
                      );
                      final reduced = reducedMotion(context);
                      return Padding(
                        key: ValueKey(exercise.id),
                        padding: const EdgeInsets.only(top: 10),
                        // Same collapse-before-remove / stagger-in pair as
                        // the day list above (see its comment).
                        child: AnimatedSize(
                          duration: reduced
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          curve: Curves.easeIn,
                          alignment: Alignment.topCenter,
                          child: AnimatedOpacity(
                            opacity: removing ? 0 : 1,
                            duration: reduced
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            child: removing
                                ? const SizedBox(width: double.infinity)
                                : StaggeredReveal(
                                    index: ei,
                                    child: ReorderableDelayedDragStartListener(
                                      index: ei,
                                      child: _ExerciseRow(
                                        exercise: exercise,
                                        onEdit: () => widget.onEditExercise(ei),
                                        onRemove: () =>
                                            widget.onRemoveExercise(ei),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 10),
                _AddButton(
                  label: 'Add exercise',
                  onTap: widget.onAddExercise,
                  compact: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One exercise within a day card — tapping it opens the exercise sheet
/// pre-filled for editing in place; the trailing X stays a separate, direct
/// remove action.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.exercise,
    required this.onEdit,
    required this.onRemove,
  });

  final PlannedExercise exercise;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: TrainColors.glassStrong,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          height: 1.5,
                          color: TrainColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _setSpecLabel(exercise),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.mono(
                          size: 10.5,
                          tracking: 0.06,
                          color: TrainColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                PressableScale(
                  child: IconButton(
                    onPressed: onRemove,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: TrainColors.ink4,
                    ),
                    splashRadius: 18,
                    tooltip: 'Remove exercise',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "3 × 6–8 · 60kg · rest 1:30" — the compact set spec read back off the
  /// generated sets (all identical for a manually-added exercise).
  String _setSpecLabel(PlannedExercise e) {
    if (e.sets.isEmpty) return 'No sets';
    final first = e.sets.first;
    final parts = <String>[
      '${e.sets.length} × ${repTargetLabel(first.repTarget)}',
      if (first.targetWeightKg != null)
        '${_trimWeight(first.targetWeightKg!)}kg',
      'rest ${restLabel(first.restSeconds)}',
    ];
    return parts.join(' · ');
  }
}

/// A sheet to add one day: a slot letter, a label, and optional notes.
class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.suggestedSlot});

  final String suggestedSlot;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  late final TextEditingController _slot = TextEditingController(
    text: widget.suggestedSlot,
  );
  final TextEditingController _label = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    _label.addListener(() {
      final canAdd = _label.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _slot.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canAdd) return;
    final slot = _slot.text.trim().isEmpty
        ? widget.suggestedSlot
        : _slot.text.trim();
    final notes = _notes.text.trim();
    Navigator.of(context).pop(
      _DayDraft(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        slot: slot,
        label: _label.text.trim(),
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Add day',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: _LabeledField(label: 'Slot', controller: _slot, hint: 'A'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LabeledField(
                fieldKey: const Key('day-label-field'),
                label: 'Label',
                controller: _label,
                hint: 'Push / Pull / Legs',
                autofocus: true,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _LabeledField(label: 'Notes (optional)', controller: _notes, hint: '—'),
        const SizedBox(height: 22),
        PillButton(
          label: 'Add day',
          icon: Icons.add_rounded,
          color: TrainColors.green,
          enabled: _canAdd,
          onTap: _submit,
        ),
      ],
    );
  }
}

enum _RepMode { fixed, range, toFailure }

/// A sheet to add or edit one exercise via a compact set spec: name, muscle
/// group, a set count, a rep target (fixed / range / to-failure), a rest
/// wheel, and an optional weight — which it expands into that many identical
/// working sets. Passing [initial] pre-fills every field from that exercise
/// and, on submit, keeps its id so the caller can replace it in place rather
/// than append a new one.
class _ExerciseSheet extends StatefulWidget {
  const _ExerciseSheet({this.initial});

  final PlannedExercise? initial;

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _muscle = TextEditingController();
  final TextEditingController _sets = TextEditingController(text: '3');
  final TextEditingController _reps = TextEditingController(text: '8');
  final TextEditingController _repsMax = TextEditingController(text: '12');
  final TextEditingController _weight = TextEditingController();
  _RepMode _mode = _RepMode.range;
  int _restSeconds = 90;
  bool _canAdd = false;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _name.text = initial.name;
      _muscle.text = initial.muscleGroup ?? '';
      _sets.text = '${initial.sets.length}';
      final first = initial.sets.isNotEmpty ? initial.sets.first : null;
      if (first != null) {
        _mode = switch (first.repTarget.kind) {
          RepTargetKind.fixed => _RepMode.fixed,
          RepTargetKind.range => _RepMode.range,
          RepTargetKind.toFailure => _RepMode.toFailure,
        };
        if (first.repTarget.min != null) _reps.text = '${first.repTarget.min}';
        if (first.repTarget.max != null) {
          _repsMax.text = '${first.repTarget.max}';
        }
        if (first.targetWeightKg != null) {
          _weight.text = _trimWeight(first.targetWeightKg!);
        }
        _restSeconds = first.restSeconds;
      } else {
        _restSeconds = initial.defaultRestSeconds;
      }
    }
    _canAdd = _name.text.trim().isNotEmpty;
    _name.addListener(() {
      final canAdd = _name.text.trim().isNotEmpty;
      if (canAdd != _canAdd) setState(() => _canAdd = canAdd);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _muscle.dispose();
    _sets.dispose();
    _reps.dispose();
    _repsMax.dispose();
    _weight.dispose();
    super.dispose();
  }

  RepTarget _buildTarget() {
    switch (_mode) {
      case _RepMode.fixed:
        final reps = int.tryParse(_reps.text.trim()) ?? 1;
        return RepTarget.fixed(reps < 1 ? 1 : reps);
      case _RepMode.range:
        var lo = int.tryParse(_reps.text.trim()) ?? 1;
        var hi = int.tryParse(_repsMax.text.trim()) ?? lo;
        if (lo < 1) lo = 1;
        if (hi < lo) hi = lo;
        return RepTarget.range(lo, hi);
      case _RepMode.toFailure:
        return const RepTarget.toFailure();
    }
  }

  void _submit() {
    if (!_canAdd) return;
    final count = (int.tryParse(_sets.text.trim()) ?? 1).clamp(1, 20);
    final weightRaw = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    final weight = (weightRaw == null || weightRaw <= 0) ? null : weightRaw;
    final target = _buildTarget();
    final muscle = _muscle.text.trim();
    final initial = widget.initial;
    Navigator.of(context).pop(
      PlannedExercise(
        id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        order: initial?.order ?? 0,
        muscleGroup: muscle.isEmpty ? null : muscle,
        defaultRestSeconds: _restSeconds,
        sets: [
          for (var i = 0; i < count; i++)
            PlannedSet(
              order: i,
              repTarget: target,
              restSeconds: _restSeconds,
              targetWeightKg: weight,
              type: SetType.working,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: _editing ? 'Edit exercise' : 'Add exercise',
      children: [
        _LabeledField(
          fieldKey: const Key('exercise-name-field'),
          label: 'Name',
          controller: _name,
          hint: 'Bench Press',
          autofocus: !_editing,
        ),
        const SizedBox(height: 14),
        _LabeledField(
          label: 'Muscle group (optional)',
          controller: _muscle,
          hint: 'Chest',
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: _NumberField(label: 'Sets', controller: _sets),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REP TARGET',
                    style: TrainType.mono(
                      size: 10.5,
                      tracking: 0.06,
                      color: TrainColors.ink4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    // SelectChip is a shared capture-widgets component (also
                    // used by diet/schedule, outside this batch's scope) with
                    // no press feedback of its own — wrapped locally here
                    // rather than editing the shared widget.
                    children: [
                      PressableScale(
                        child: SelectChip(
                          label: 'Fixed',
                          selected: _mode == _RepMode.fixed,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _mode = _RepMode.fixed);
                          },
                        ),
                      ),
                      PressableScale(
                        child: SelectChip(
                          label: 'Range',
                          selected: _mode == _RepMode.range,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _mode = _RepMode.range);
                          },
                        ),
                      ),
                      PressableScale(
                        child: SelectChip(
                          label: 'To failure',
                          selected: _mode == _RepMode.toFailure,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _mode = _RepMode.toFailure);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_mode != _RepMode.toFailure) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: _mode == _RepMode.range ? 'Min reps' : 'Reps',
                  controller: _reps,
                ),
              ),
              if (_mode == _RepMode.range) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(label: 'Max reps', controller: _repsMax),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RestPicker(
                initialSeconds: _restSeconds,
                onChanged: (v) => _restSeconds = v,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: 'Weight (kg)',
                controller: _weight,
                hint: '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        PillButton(
          label: _editing ? 'Save changes' : 'Add exercise',
          icon: _editing ? Icons.check_rounded : Icons.add_rounded,
          color: TrainColors.ember,
          enabled: _canAdd,
          onTap: _submit,
        ),
      ],
    );
  }
}

/// A dark, physical rest-duration wheel — 5s increments up to 5:00, with a
/// native scroll-tick haptic on every value that settles under the band.
/// Replaces a free-text seconds field: rest is a duration people dial in by
/// feel, not a number they type.
class _RestPicker extends StatefulWidget {
  const _RestPicker({required this.initialSeconds, required this.onChanged});

  final int initialSeconds;
  final ValueChanged<int> onChanged;

  @override
  State<_RestPicker> createState() => _RestPickerState();
}

class _RestPickerState extends State<_RestPicker> {
  static const _stepSeconds = 5;
  static const _maxSeconds = 300;

  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(
        initialItem:
            widget.initialSeconds.clamp(0, _maxSeconds) ~/ _stepSeconds,
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REST',
          style: TrainType.mono(
            size: 10.5,
            tracking: 0.06,
            color: TrainColors.ink4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 132,
          decoration: BoxDecoration(
            color: TrainColors.glassStrong,
            borderRadius: BorderRadius.circular(14),
          ),
          child: CupertinoPicker(
            key: const Key('rest-picker'),
            scrollController: _controller,
            itemExtent: 34,
            diameterRatio: 1.4,
            backgroundColor: Colors.transparent,
            selectionOverlay: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: TrainColors.hairline,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onSelectedItemChanged: (index) {
              if (!reducedMotion(context)) HapticFeedback.selectionClick();
              widget.onChanged(index * _stepSeconds);
            },
            children: [
              for (var s = 0; s <= _maxSeconds; s += _stepSeconds)
                Center(
                  child: Text(
                    restLabel(s),
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w700,
                      height: 1.1,
                      color: TrainColors.ink,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The shared bottom-sheet chrome (grabber + title + content), matching the
/// session/plan screens' dark palette.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Color(0x08FFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          top: 12,
          left: 22,
          right: 22,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: TrainColors.hairline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 12),
              child: Text(
                title,
                style: TrainType.ui(
                  size: 20,
                  weight: FontWeight.w800,
                  tracking: -0.025,
                  height: 1.15,
                  color: TrainColors.ink,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A labelled single-line text field for the sheets.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.onSubmitted,
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TrainType.mono(
            size: 10.5,
            tracking: 0.06,
            color: TrainColors.ink4,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          textInputAction: TextInputAction.next,
          onSubmitted: onSubmitted,
          cursorColor: TrainColors.green,
          style: TrainType.ui(
            size: 15,
            weight: FontWeight.w700,
            height: 1.1,
            color: TrainColors.ink,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: TrainColors.hairline),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: TrainColors.hairline),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: TrainColors.green, width: 1.6),
            ),
            hintText: hint,
            hintStyle: TrainType.ui(
              size: 15,
              weight: FontWeight.w700,
              height: 1.1,
              color: TrainColors.ink4,
            ),
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TrainType.mono(
            size: 10.5,
            tracking: 0.06,
            color: TrainColors.ink4,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          cursorColor: TrainColors.green,
          style: TrainType.ui(
            size: 15,
            weight: FontWeight.w700,
            height: 1.1,
            color: TrainColors.ink,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TrainType.ui(
              size: 15,
              weight: FontWeight.w700,
              height: 1.1,
              color: TrainColors.ink4,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
            filled: true,
            fillColor: TrainColors.glassStrong,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: TrainColors.green,
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
