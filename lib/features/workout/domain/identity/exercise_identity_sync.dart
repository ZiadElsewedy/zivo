import 'dart:async';

import '../live_session.dart';
import '../workout_plan.dart';
import '../workout_plan_repository.dart';
import '../workout_session_repository.dart';
import 'exercise_library_repository.dart';
import 'identity_reconcile.dart';

/// Runs [reconcileExerciseIdentities] against the real repositories — the
/// one-time identity migration on an existing account, and the ongoing sync
/// that links whatever a new import, a plan edit or a mid-workout swap
/// introduced.
///
/// Wired at app root like `SessionMaintenance`: on sign-in, on resume, and
/// shortly after the splits change. It is safe to run any number of times —
/// a pass that finds nothing writes nothing — and it never touches a logged
/// session.
///
/// **It only writes once it can see everything.** An identity pass over a
/// library that hasn't loaded yet would mint duplicates of every exercise
/// that already exists, so it waits for the library, the splits and the
/// history to have each delivered a real snapshot, and gives up quietly if
/// they don't (offline at launch, say) — the next trigger tries again.
class ExerciseIdentitySync {
  ExerciseIdentitySync({
    required WorkoutPlanRepository plans,
    required WorkoutSessionRepository sessions,
    required ExerciseLibraryRepository library,
    DateTime Function()? now,
    this.loadTimeout = const Duration(seconds: 20),
    // A named parameter cannot start with an underscore.
    // ignore: prefer_initializing_formals
  }) : _plans = plans,
       // ignore: prefer_initializing_formals
       _sessions = sessions,
       // ignore: prefer_initializing_formals
       _library = library,
       _now = now ?? DateTime.now;

  final WorkoutPlanRepository _plans;
  final WorkoutSessionRepository _sessions;
  final ExerciseLibraryRepository _library;
  final DateTime Function() _now;
  final Duration loadTimeout;

  Future<IdentityReconciliation>? _inFlight;
  Timer? _debounce;
  StreamSubscription<List<WorkoutPlan>>? _splitsSub;

  /// One pass. Concurrent calls share the pass already running.
  Future<IdentityReconciliation> run() =>
      _inFlight ??= _run().whenComplete(() => _inFlight = null);

  /// Re-runs a moment after the splits change, so an imported or edited
  /// plan's exercises are linked without waiting for the next launch.
  void watchSplits({Duration delay = const Duration(seconds: 3)}) {
    _splitsSub ??= _plans.watchSplits().listen(
      (_) {
        _debounce?.cancel();
        _debounce = Timer(delay, () => unawaited(run()));
      },
      onError: (Object _) {},
    );
  }

  void dispose() {
    _debounce?.cancel();
    unawaited(_splitsSub?.cancel());
  }

  Future<IdentityReconciliation> _run() async {
    try {
      final library = await _library
          .watch()
          .firstWhere((l) => l.loaded)
          .timeout(loadTimeout);
      final splits = await _plans.watchSplits().first.timeout(loadTimeout);
      final List<LiveSession> sessions = await _sessions
          .watchAll()
          .first
          .timeout(loadTimeout);

      final plan = reconcileExerciseIdentities(
        splits: splits,
        sessions: sessions,
        library: library,
        now: _now(),
      );
      if (plan.isEmpty) return plan;

      // Identities first, then the mapping into them, then the plans that
      // point at them — so no reader ever meets a pointer to nothing.
      await _library.saveExercises(plan.exercises);
      await _library.saveAliases(plan.aliases);
      if (plan.slotIdentities.isNotEmpty) {
        // The LIVE copy, not the snapshot the pass read: a plan edited in
        // the meantime keeps its edit, and only empty identities are filled.
        for (final split in _plans.splits) {
          final linked = applySlotIdentities(split, plan.slotIdentities);
          if (!identical(linked, split)) await _plans.saveSplit(linked);
        }
      }
      return plan;
    } on TimeoutException {
      return IdentityReconciliation.none;
    } catch (_) {
      // Signed out mid-pass, rules not deployed, offline: nothing written is
      // ever half-meaningful (each layer is additive and read-side), and the
      // next trigger simply tries again.
      return IdentityReconciliation.none;
    }
  }
}
