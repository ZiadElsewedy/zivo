import 'package:flutter/material.dart';

import '../../domain/planned_exercise.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_repository.dart';
import '../../domain/workout_plan_source.dart';
import '../../domain/workout_plan_status.dart';

/// A mutable day while editing — its exercises are fully-formed
/// [PlannedExercise]s (built by the exercise sheet), so drafts round-trip
/// losslessly through save.
class DayDraft {
  DayDraft({
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

/// The split editor's document: the days being edited, and the rules for
/// turning them back into a [WorkoutPlan].
///
/// Split out of a 1,813-line page ([ADR-008](../../../../docs/DECISIONS/ADR-008-presentation-controllers.md))
/// for one reason above the others: **the rotation cursor**. A plan stores
/// `cycleCursor` as an *index*, but the editor lets days be dragged into a new
/// order, so the cursor has to be tracked by day *identity* through the whole
/// edit and resolved back to an index only on save — otherwise reordering
/// silently changes which workout Home offers you next. That rule was 30 lines
/// buried in a `_save` method inside a `State`; it is now a property of this
/// class, and testable as one.
///
/// It holds no `BuildContext` and never navigates. Every sheet the editor
/// opens (add day, add/edit exercise, bulk rest) is the page's job — the page
/// shows it and hands the result here.
class PlanEditController extends ChangeNotifier {
  PlanEditController({WorkoutPlan? initialPlan, required this.asSplit})
    : _initialPlan = initialPlan,
      planId =
          initialPlan?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt = initialPlan?.createdAt ?? DateTime.now(),
      // Tracked by IDENTITY rather than the raw index [WorkoutPlan.cycleCursor]
      // stores, so reordering days keeps the rotation pointed at the SAME
      // logical "next day" in its new position. Null for a new plan — nothing
      // to preserve; a fresh plan just starts its rotation at day 0.
      cursorDayId = (initialPlan == null || initialPlan.days.isEmpty)
          ? null
          : initialPlan.days
                .firstWhere(
                  (d) => d.order == initialPlan.cycleCursor,
                  orElse: () => initialPlan.days.first,
                )
                .id {
    name = TextEditingController(text: initialPlan?.name ?? '');
    if (initialPlan != null) {
      _days.addAll(
        initialPlan.days.map(
          (d) => DayDraft(
            id: d.id,
            slot: d.slot,
            label: d.label,
            notes: d.notes,
            exercises: List.of(d.exercises),
          ),
        ),
      );
    }
    name.addListener(_recompute);
    _recompute();
  }

  final WorkoutPlan? _initialPlan;

  /// Whether this edits a *split* (the multi-split library) or the single
  /// active plan — they persist and delete through different repository
  /// methods.
  final bool asSplit;

  final String planId;
  final DateTime createdAt;
  final String? cursorDayId;

  late final TextEditingController name;

  final List<DayDraft> _days = [];
  List<DayDraft> get days => _days;

  bool _canSave = false;
  bool get canSave => _canSave;

  bool get isEditing => _initialPlan != null;

  void _recompute() {
    final next = name.text.trim().isNotEmpty && _days.isNotEmpty;
    if (next != _canSave) {
      _canSave = next;
      notifyListeners();
    }
  }

  /// The next cycle slot letter for a plan that already has this many days:
  /// A, B, C… (falls back to a number past Z).
  String get nextSlot => _days.length < 26
      ? String.fromCharCode(0x41 + _days.length)
      : '${_days.length + 1}';

  /// The wheel's seed when opening the default-rest sheet — the first
  /// exercise's own rest if there is one, so re-opening it after already
  /// bulk-setting a value starts from that value rather than always 1:30.
  int get seedRest {
    for (final day in _days) {
      for (final exercise in day.exercises) {
        return exercise.defaultRestSeconds;
      }
    }
    return 90;
  }

  // ---- Days ----------------------------------------------------------------

  void addDay(DayDraft day) {
    _days.add(day);
    notifyListeners();
    _recompute();
  }

  void removeDay(String id) {
    _days.removeWhere((d) => d.id == id);
    notifyListeners();
    _recompute();
  }

  /// Wired to `onReorderItem`, so [newIndex] already arrives as the final
  /// insert position. Cursor identity is untouched here — it is resolved back
  /// to an index from the day's id in [buildPlan], so it follows wherever that
  /// day ends up.
  void reorderDays(int oldIndex, int newIndex) {
    _days.insert(newIndex, _days.removeAt(oldIndex));
    notifyListeners();
  }

  // ---- Exercises -----------------------------------------------------------

  void addExercise(int dayIndex, PlannedExercise exercise) {
    _days[dayIndex].exercises.add(exercise);
    notifyListeners();
  }

  /// Replaces an exercise in place, so editing one no longer means deleting
  /// and re-adding it (which lost its position in the day and its id).
  void replaceExercise(
    int dayIndex,
    int exerciseIndex,
    PlannedExercise exercise,
  ) {
    _days[dayIndex].exercises[exerciseIndex] = exercise;
    notifyListeners();
  }

  void removeExercise(int dayIndex, String exerciseId) {
    _days[dayIndex].exercises.removeWhere((e) => e.id == exerciseId);
    notifyListeners();
  }

  void reorderExercises(int dayIndex, int oldIndex, int newIndex) {
    final exercises = _days[dayIndex].exercises;
    exercises.insert(newIndex, exercises.removeAt(oldIndex));
    notifyListeners();
  }

  /// Sets EVERY exercise's rest, across every day, to one chosen value — the
  /// bulk counterpart to the per-exercise override. Per-exercise overrides
  /// made *after* this still stick; a later bulk apply overwrites them again,
  /// same as re-running any bulk action.
  void applyDefaultRest(int seconds) {
    for (final day in _days) {
      for (var i = 0; i < day.exercises.length; i++) {
        final exercise = day.exercises[i];
        day.exercises[i] = exercise.copyWith(
          defaultRestSeconds: seconds,
          sets: [
            for (final set in exercise.sets) set.copyWith(restSeconds: seconds),
          ],
        );
      }
    }
    notifyListeners();
  }

  // ---- Persistence ---------------------------------------------------------

  /// The drafts as a [WorkoutPlan]. Pure — no repository, no clock beyond
  /// `updatedAt`, so the cursor rule below can be asserted directly.
  WorkoutPlan buildPlan({DateTime? now}) {
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
    // Follow the SAME day the cursor pointed at through any reorder — not a
    // fixed index. Falls back to day 0 for a new plan (nothing to preserve) or
    // if that day was removed since (nothing sensible left to point at).
    final cursorIndex = cursorDayId == null
        ? -1
        : days.indexWhere((d) => d.id == cursorDayId);
    return WorkoutPlan(
      id: planId,
      name: name.text.trim(),
      status: WorkoutPlanStatus.active,
      // Preserves an imported draft's `pdf` marker through the mandatory
      // review step (WORKOUT_SYSTEM.md §3.4) — only a genuinely new plan
      // defaults to `manual`.
      source: _initialPlan?.source ?? WorkoutPlanSource.manual,
      createdAt: createdAt,
      updatedAt: now ?? DateTime.now(),
      cycleCursor: days.isEmpty ? 0 : (cursorIndex >= 0 ? cursorIndex : 0),
      days: days,
    );
  }

  /// Persists the plan and returns it, or null if it isn't saveable yet. The
  /// caller pops with the result.
  Future<WorkoutPlan?> save(WorkoutPlanRepository plans) async {
    if (!_canSave) return null;
    final plan = buildPlan();
    if (asSplit) {
      await plans.saveSplit(plan);
    } else {
      await plans.savePlan(plan);
    }
    return plan;
  }

  /// Deletes the plan being edited. The caller owns the confirmation prompt
  /// and the pop; this only runs once that has been agreed to.
  Future<void> delete(WorkoutPlanRepository plans) async {
    final plan = _initialPlan;
    if (plan == null) return;
    if (asSplit) {
      await plans.deleteSplit(plan.id);
    } else {
      await plans.deletePlan(plan.id);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }
}
