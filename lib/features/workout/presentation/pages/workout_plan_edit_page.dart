import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/workout_plan.dart';
import '../widgets/staggered_reveal.dart';
import '../controllers/plan_edit_controller.dart';
import '../widgets/plan_edit/day_card.dart';
import '../widgets/plan_edit/day_sheet.dart';
import '../widgets/plan_edit/default_rest.dart';
import '../widgets/plan_edit/exercise_sheet.dart';
import '../widgets/plan_edit/plan_edit_chrome.dart';
import '../../../../l10n/l10n.dart';

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
  /// The document being edited — days, the name, the rotation-cursor rule,
  /// and save/delete. See [PlanEditController]; this State owns the sheets it
  /// opens, the remove animations, and `build`.
  late final PlanEditController _c = PlanEditController(
    initialPlan: widget.initialPlan,
    asSplit: widget.asSplit,
  )..addListener(_onControllerChanged);

  /// Day/exercise ids mid-way through their remove animation — still present
  /// in the controller's days (so save stays correct if the removal is somehow
  /// interrupted) but rendered as collapsing/fading rather than gone
  /// instantly. Pure view state: the controller has no idea a row is fading.
  final Set<String> _removingDayIds = {};
  final Set<String> _removingExerciseIds = {};

  /// Days added during this editing session — they start expanded, since
  /// adding a day is immediately followed by adding exercises to it. Days
  /// loaded from an existing plan start collapsed. Membership only matters the
  /// moment a `DayCard`'s State is first created for that id, so this is never
  /// pruned.
  final Set<String> _autoExpandDayIds = {};

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  // ---- Sheets (the page's job: the controller never opens one) -------------

  Future<void> _addDay() async {
    final result = await showZivoSheet<DayDraft>(
      context: context,
      builder: (_) => DaySheet(suggestedSlot: _c.nextSlot),
    );
    if (result == null) return;
    HapticFeedback.lightImpact();
    _autoExpandDayIds.add(result.id);
    _c.addDay(result);
  }

  Future<void> _addExercise(int dayIndex) async {
    final exercise = await showZivoSheet<PlannedExercise>(
      context: context,
      builder: (_) => const ExerciseSheet(),
    );
    if (exercise == null) return;
    HapticFeedback.lightImpact();
    _c.addExercise(dayIndex, exercise);
  }

  /// Opens the exercise sheet pre-filled with the exercise already at
  /// [exerciseIndex] and, on save, replaces it in place.
  Future<void> _editExercise(int dayIndex, int exerciseIndex) async {
    final exercise = await showZivoSheet<PlannedExercise>(
      context: context,
      builder: (_) =>
          ExerciseSheet(initial: _c.days[dayIndex].exercises[exerciseIndex]),
    );
    if (exercise == null) return;
    _c.replaceExercise(dayIndex, exerciseIndex, exercise);
  }

  Future<void> _pickDefaultRest() async {
    final seconds = await showZivoSheet<int>(
      context: context,
      builder: (_) => DefaultRestSheet(initialSeconds: _c.seedRest),
    );
    if (seconds == null) return;
    _c.applyDefaultRest(seconds);
  }

  // ---- Removal (the fade is the page's; the mutation is the controller's) --

  /// Plays a brief collapse/fade before actually removing the day, so it reads
  /// as a row shrinking away rather than an instant pop — a destructive
  /// action, hence `mediumImpact`.
  Future<void> _removeDay(int index) async {
    final day = _c.days[index];
    HapticFeedback.mediumImpact();
    if (reducedMotion(context)) {
      _c.removeDay(day.id);
      return;
    }
    setState(() => _removingDayIds.add(day.id));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _removingDayIds.remove(day.id));
    _c.removeDay(day.id);
  }

  /// Same collapse-before-remove treatment, scoped to one exercise row.
  Future<void> _removeExercise(int dayIndex, int exerciseIndex) async {
    final exercise = _c.days[dayIndex].exercises[exerciseIndex];
    HapticFeedback.mediumImpact();
    if (reducedMotion(context)) {
      _c.removeExercise(dayIndex, exercise.id);
      return;
    }
    setState(() => _removingExerciseIds.add(exercise.id));
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _removingExerciseIds.remove(exercise.id));
    _c.removeExercise(dayIndex, exercise.id);
  }

  // ---- Exits ---------------------------------------------------------------

  Future<void> _save() async {
    if (!_c.canSave) return;
    HapticFeedback.lightImpact();
    final navigator = Navigator.of(context);
    final plan = await _c.save(AppScope.of(context).workoutPlans);
    if (plan != null && mounted) navigator.pop(plan);
  }

  Future<void> _delete() async {
    final plan = widget.initialPlan;
    if (plan == null) return;
    final confirmed = await confirmDestructive(
      context,
      title: widget.asSplit
          ? l(context).splitDeleteTitlePlain
          : l(context).workoutPlanDeleteTitle,
      body: widget.asSplit
          ? l(context).splitDeleteBody
          : l(context).workoutPlanDeleteBody(plan.name),
    );
    if (!confirmed || !mounted) return;
    final navigator = Navigator.of(context);
    await _c.delete(AppScope.of(context).workoutPlans);
    if (mounted) navigator.pop();
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
                title: _c.isEditing
                    ? (widget.asSplit ? 'Edit split' : 'Edit workout plan')
                    : (widget.asSplit ? 'New split' : 'New workout plan'),
                onClose: () => Navigator.of(context).maybePop(),
                titleColor: TrainColors.ink2,
                iconColor: TrainColors.ink2,
                chipColor: TrainColors.glassStrong,
                trailing: _c.isEditing
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
                  controller: _c.name,
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
                child: DefaultRestRow(
                  seconds: _c.seedRest,
                  onTap: _pickDefaultRest,
                ),
              ),
              Expanded(
                child: _c.days.isEmpty
                    ? PlanEmptyDays(onAdd: _addDay)
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
                        itemCount: _c.days.length + 1,
                        // Default handles would make the WHOLE row (including
                        // the trailing "Add day" button) a drag target; days
                        // opt in individually via ReorderableDelayedDragStartListener
                        // below instead, and the add-button — outside that
                        // wrapper — is never draggable.
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, animation) =>
                            liftProxyDecorator(child, animation, radius: 18),
                        onReorderStart: (_) => HapticFeedback.selectionClick(),
                        onReorderEnd: (_) => HapticFeedback.lightImpact(),
                        onReorderItem: (oldIndex, newIndex) {
                          // Guards the trailing "Add day" item defensively —
                          // it always sits at _c.days.length and, since only
                          // day items are wrapped in a drag-start listener
                          // (see buildDefaultDragHandles above), never
                          // actually starts a drag in the first place.
                          if (oldIndex >= _c.days.length) return;
                          _c.reorderDays(oldIndex, newIndex);
                        },
                        itemBuilder: (context, i) {
                          if (i == _c.days.length) {
                            return PlanAddButton(
                              key: const ValueKey('add-day-button'),
                              label: 'Add day',
                              onTap: _addDay,
                            );
                          }
                          final day = _c.days[i];
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
                                              child: DayCard(
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
                                                    _c.reorderExercises(
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
                  enabled: _c.canSave,
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
